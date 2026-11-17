import Foundation
import Darwin

public struct SerialDevice: Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var isFlipper: Bool { name.lowercased().contains("flip") }
    public init(path: String) { self.path = path }
    public static func available() -> [SerialDevice] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names.filter { $0.hasPrefix("cu.") && !$0.localizedCaseInsensitiveContains("bluetooth") && $0 != "cu.debug-console" }
            .map { SerialDevice(path: "/dev/" + $0) }.sorted {
                if $0.isFlipper != $1.isFlipper { return $0.isFlipper }
                return $0.path < $1.path
            }
    }
}

public struct SerialError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

/// Owned by a single caller (the app's main actor). All I/O is nonblocking and bounded.
public final class SerialPort {
    private var descriptor: Int32 = -1
    private var original: termios?
    private var pendingWrites = Data()
    public private(set) var path: String?
    public var isOpen: Bool { descriptor >= 0 }
    public var queuedByteCount: Int { pendingWrites.count }
    public static let baudRates = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
    public init() {}
    deinit { close() }
    public func open(path: String, baud: Int = 115200) throws {
        guard !isOpen else { throw SerialError("Disconnect the current port first.") }
        guard SerialPort.baudRates.contains(baud) else { throw SerialError("Unsupported baud rate.") }
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw systemError("Cannot open \(path)") }
        var success = false
        defer { if !success { Darwin.close(fd) } }
        guard isatty(fd) == 1 else { throw SerialError("The selected path is not a serial terminal.") }
        guard ioctl(fd, TIOCEXCL) == 0 else { throw systemError("Cannot obtain exclusive serial access") }
        var settings = termios()
        guard tcgetattr(fd, &settings) == 0 else { throw systemError("Cannot read serial settings") }
        let previous = settings
        cfmakeraw(&settings)
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        settings.c_cflag &= ~tcflag_t(CSIZE | PARENB | CSTOPB | CRTSCTS)
        settings.c_cflag |= tcflag_t(CS8)
        withUnsafeMutableBytes(of: &settings.c_cc) { bytes in
            bytes[Int(VMIN)] = 0
            bytes[Int(VTIME)] = 0
        }
        cfsetispeed(&settings, speed_t(baud))
        cfsetospeed(&settings, speed_t(baud))
        guard tcsetattr(fd, TCSANOW, &settings) == 0 else { throw systemError("Cannot configure the serial port") }
        descriptor = fd; original = previous; self.path = path; success = true
    }
    public func close() {
        if descriptor >= 0 {
            if var previous = original { _ = tcsetattr(descriptor, TCSANOW, &previous) }
            _ = ioctl(descriptor, TIOCNXCL)
            _ = Darwin.close(descriptor)
        }
        descriptor = -1; original = nil; path = nil; pendingWrites.removeAll()
    }
    public func send(_ command: String, lineEnding: String = "\n") throws {
        guard isOpen else { throw SerialError("Connect to your Flipper first.") }
        let validated = try CommandValidation.validate(command)
        guard ["\n", "\r\n", "\r"].contains(lineEnding) else { throw SerialError("Unsupported line ending.") }
        let data = Data((validated + lineEnding).utf8)
        guard pendingWrites.count + data.count <= 65_536 else { throw SerialError("Serial output is busy. Wait for the device to read pending commands.") }
        pendingWrites.append(data)
        try flushWrites()
    }
    public func readAvailable() throws -> Data {
        guard isOpen else { return Data() }
        var status = pollfd(fd: descriptor, events: Int16(POLLIN | POLLOUT), revents: 0)
        if Darwin.poll(&status, 1, 0) > 0, status.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
            throw SerialError("The USB connection was lost. Reconnect the Flipper and enable USB-UART Bridge.")
        }
        try flushWrites()
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        // Bound each pass so continuous traffic cannot starve the UI.
        for _ in 0..<16 {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 { result.append(contentsOf: buffer.prefix(count)) }
            else if count == 0 { break }
            else if errno == EAGAIN || errno == EWOULDBLOCK { break }
            else if errno == EINTR { continue }
            else { throw systemError("Serial read failed") }
        }
        return result
    }
    private func flushWrites() throws {
        while !pendingWrites.isEmpty {
            let written = pendingWrites.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress!, $0.count) }
            if written > 0 { pendingWrites.removeFirst(written) }
            else if written == 0 || errno == EAGAIN || errno == EWOULDBLOCK { return }
            else if errno == EINTR { continue }
            else { throw systemError("Serial write failed") }
        }
    }
    private func systemError(_ prefix: String) -> SerialError {
        let code = errno
        let hint = code == EBUSY ? " Close qFlipper or any other serial application using this port." : ""
        return SerialError("\(prefix): \(String(cString: strerror(code))).\(hint)")
    }
}
