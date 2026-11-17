import Foundation
import Darwin
import MarauderCore

/// Exercises the real termios/read/write implementation with an isolated pseudo-terminal.
/// Does not open the user's Flipper or transmit wireless commands.
func serialRoundTripCheck() throws {
    var master: Int32 = -1
    var slave: Int32 = -1
    var name = [CChar](repeating: 0, count: 1024)
    guard openpty(&master, &slave, &name, nil, nil) == 0 else {
        throw CheckSkipped("Pseudo-terminal creation is unavailable: \(String(cString: strerror(errno)))")
    }
    defer { if master >= 0 { Darwin.close(master) }; if slave >= 0 { Darwin.close(slave) } }
    let path = String(cString: name)
    let port = SerialPort()
    do { try port.open(path: path) }
    catch {
        if error.localizedDescription.contains("Operation not permitted") { throw CheckSkipped("Sandbox blocks the pseudo-terminal device") }
        throw error
    }
    defer { port.close() }
    _ = fcntl(master, F_SETFL, O_NONBLOCK)
    try port.send("info", lineEnding: "\r\n")
    var buffer = [UInt8](repeating: 0, count: 4096)
    var sent = Data()
    for _ in 0..<20 {
        let count = Darwin.read(master, &buffer, buffer.count)
        if count > 0 { sent.append(contentsOf: buffer.prefix(count)) }
        if sent.count >= 6 { break }
        Thread.sleep(forTimeInterval: 0.01)
    }
    expectEqual(String(decoding: sent, as: UTF8.self), "info\r\n")
    let response = Data("ESP32 Marauder\r\n-44 Ch: 1 AA:BB:CC:DD:EE:FF ESSID: Test\n".utf8)
    let written = response.withUnsafeBytes { Darwin.write(master, $0.baseAddress!, $0.count) }
    expectEqual(written, response.count)
    var received = Data()
    for _ in 0..<20 {
        received.append(try port.readAvailable())
        if received.count >= response.count { break }
        Thread.sleep(forTimeInterval: 0.01)
    }
    expectEqual(received, response)
    var framer = LineFramer()
    let lines = framer.append(received)
    expectEqual(lines.count, 2)
    expectEqual(MarauderParser.parse(lines[1]), .accessPoint(bssid: "AA:BB:CC:DD:EE:FF", ssid: "Test", channel: 1, rssi: -44))
    port.close()
    expectFalse(port.isOpen)
    expectEqual(port.queuedByteCount, 0)
    expectThrows(try port.send("help"))
}

struct CheckSkipped: Error { let reason: String; init(_ reason: String) { self.reason = reason } }
