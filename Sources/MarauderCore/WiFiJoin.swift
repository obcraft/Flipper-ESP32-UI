import Foundation

public struct WiFiJoinCommand {
    public let wireValue: String

    public init(index: Int, password: String) throws {
        guard (0...65535).contains(index) else { throw ValidationError("Invalid firmware AP index.") }
        try Self.validatePassword(password)
        if password.isEmpty {
            // The CLI only keeps an empty argument if another token follows it.
            wireValue = #"join -p "" -a "# + String(index)
        } else {
            // Marauder's tokenizer supports both quote styles but has no backslash escapes.
            let quoted = password.replacingOccurrences(of: "\"", with: "\"'\"'\"")
            wireValue = "join -a \(index) -p \"\(quoted)\""
        }
    }

    public static func validatePassword(_ password: String) throws {
        guard !password.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ValidationError("The Wi-Fi password contains a control character.")
        }
        let bytes = password.utf8
        guard bytes.isEmpty || (8...63).contains(bytes.count)
                || (bytes.count == 64 && bytes.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })) else {
            throw ValidationError("Enter an 8–63 byte password or a 64-digit hexadecimal key.")
        }
    }

    public static func isJoinCommand(_ line: String) -> Bool {
        var command = line[...].drop(while: \.isWhitespace)
        if command.first == ">" { command = command.dropFirst().drop(while: \.isWhitespace) }
        if command.first == "#" { command = command.dropFirst() }
        return command.split(whereSeparator: \.isWhitespace).first?.lowercased() == "join"
    }
}

/// Drives the documented v1.20 serial exchange. The AP list omits BSSIDs, so
/// each matching index is verified with the firmware's per-AP info command.
public struct WiFiJoin {
    public enum Step: Equatable {
        case stopping, listing, verifying(Int), joining

        public var message: String {
            switch self {
            case .stopping: return "Stopping radio activity…"
            case .listing: return "Refreshing the firmware’s AP list…"
            case .verifying: return "Verifying the selected access point…"
            case .joining: return "Connecting the ESP32 to Wi-Fi…"
            }
        }

        public var timeout: TimeInterval { self == .joining ? 20 : 6 }
    }

    public enum Update {
        case send(String)
        case sendCredentials(WiFiJoinCommand)
        case joined
    }

    public let target: AccessPoint
    public private(set) var step: Step = .stopping
    private var password: String
    private var candidates: ArraySlice<Int> = []
    private var listingStarted = false
    private var listings: [APListing] = []
    private var reportedBSSID: String?
    private var reportedChannel: Int?
    private var reportedSSID: String?
    private var usingTargetSSID = false

    public static func canJoin(_ ap: AccessPoint) -> Bool {
        (1...14).contains(ap.channel) && !ap.isHidden && ap.bssid.map(CommandValidation.mac) == true
    }

    public init(target: AccessPoint, password: String) throws {
        guard Self.canJoin(target) else {
            throw ValidationError("Select a named 2.4 GHz access point discovered by the ESP32.")
        }
        try WiFiJoinCommand.validatePassword(password)
        self.target = target
        self.password = password
    }

    public mutating func receive(_ line: String) throws -> Update? {
        let reply = line.hasPrefix("> ") ? String(line.dropFirst(2)) : line
        let lower = reply.lowercased()
        if lower.hasPrefix("unknown command") || lower.hasPrefix("invalid command") || lower.contains("command not found") && lower.hasPrefix("error") {
            throw ValidationError("The firmware rejected a Wi-Fi join command. Check that it supports Join WiFi.")
        }
        switch step {
        case .stopping:
            guard ["stopping wifi tran/recv", "stopped scanning."].contains(lower) else { return nil }
            step = .listing
            return .send("list -a")
        case .listing:
            if reply == "#list -a" { listingStarted = true; listings.removeAll() }
            guard listingStarted else { return nil }
            if case let .listing(row)? = MarauderParser.parse(reply) { listings.append(row) }
            guard reply.hasSuffix(" selected"), Int(reply.dropLast(" selected".count)) != nil else { return nil }
            if listings.contains(where: { $0.ssid == target.ssid && !(1...14).contains($0.channel) }) {
                throw ValidationError("This network also appears outside 2.4 GHz. The firmware joins by name. Select a network with a distinct 2.4 GHz name.")
            }
            candidates = listings.filter { $0.channel == target.channel && $0.ssid == target.ssid }.map(\.index)[...]
            return try verifyNextCandidate()
        case .verifying(let index):
            if reply.hasPrefix("BSSID: ") { reportedBSSID = String(reply.dropFirst("BSSID: ".count)).uppercased() }
            if reply.hasPrefix("Channel: ") { reportedChannel = Int(reply.dropFirst("Channel: ".count)) }
            if reply.hasPrefix("ESSID: ") { reportedSSID = String(reply.dropFirst("ESSID: ".count)) }
            guard reply.hasPrefix("Security: ") else { return nil }
            guard reportedBSSID == target.bssid?.uppercased(), reportedChannel == target.channel, reportedSSID == target.ssid else {
                return try verifyNextCandidate()
            }
            let command = try WiFiJoinCommand(index: index, password: password)
            password = ""
            step = .joining
            return .sendCredentials(command)
        case .joining:
            if reply.hasPrefix("Using SSID: ") {
                guard reply == "Using SSID: \(target.ssid)" else {
                    throw ValidationError("The firmware reported a different network name.")
                }
                usingTargetSSID = true
            }
            if lower == "could not connect to wifi network" || lower == "failed to connect" {
                throw ValidationError("The ESP32 could not join the network. Check the password and signal, then try again.")
            }
            if lower == "you did not provide the proper args" {
                throw ValidationError("The firmware rejected the Wi-Fi join arguments.")
            }
            if usingTargetSSID && (Self.isCompletionPrompt(line) || lower == "connected!" || lower == "connected to wifi") {
                return .joined
            }
            return nil
        }
    }

    public static func isCompletionPrompt(_ line: String) -> Bool {
        let line = line.trimmingCharacters(in: .whitespaces)
        // On a fresh v1.20 join, the prompt follows the progress dots with no
        // line break. If already connected to the same SSID, only the prompt prints.
        if line == ">" { return true }
        let prefix = "Connecting to WiFi"
        return line.hasPrefix(prefix) && line.last == ">" && line.dropFirst(prefix.count).dropLast().allSatisfy { $0 == "." }
    }

    private mutating func verifyNextCandidate() throws -> Update {
        guard let index = candidates.popFirst(), (0...65535).contains(index) else {
            throw ValidationError("The selected access point could not be verified in the firmware’s AP list. Scan again and retry.")
        }
        step = .verifying(index)
        reportedBSSID = nil
        reportedChannel = nil
        reportedSSID = nil
        return .send("info -a \(index)")
    }
}
