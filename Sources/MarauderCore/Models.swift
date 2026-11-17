import Foundation

public struct Station: Identifiable, Equatable, Codable {
    public var id: String { mac }
    public var mac: String
    public var index: Int?
    public var lastSeen: Date
}

public struct AccessPoint: Identifiable, Equatable, Codable {
    public var id: String
    public var bssid: String?
    public var ssid: String
    public var channel: Int
    public var rssi: Int?
    public var index: Int?
    public var selected = false
    public var lastSeen: Date?
    public var stations: [Station] = []
    public var isHidden: Bool { ssid.isEmpty || ssid == "[hidden]" || ssid.uppercased() == bssid }
    public var displayName: String { isHidden ? "Hidden network" : ssid }
}

public struct APListing: Equatable {
    public let index: Int
    public let channel: Int
    public let ssid: String
    public let rssi: Int?
    public let selected: Bool
    public init(index: Int, channel: Int, ssid: String, rssi: Int?, selected: Bool) {
        self.index = index; self.channel = channel; self.ssid = ssid; self.rssi = rssi; self.selected = selected
    }
}

public enum ParsedEvent: Equatable {
    case accessPoint(bssid: String, ssid: String, channel: Int, rssi: Int)
    case listing(APListing)
    case station(ap: String, mac: String)
    case resetAccessPoints
}

/// Incremental, bounded framing. Decode after newline so split UTF-8 bytes survive USB reads.
public struct LineFramer {
    private var pending = Data()
    private var dropping = false
    public let maximumLineBytes: Int
    public private(set) var droppedLines = 0
    public init(maximumLineBytes: Int = 32_768) { self.maximumLineBytes = maximumLineBytes }
    public mutating func append(_ data: Data) -> [String] {
        var lines: [String] = []
        for byte in data {
            if byte == 10 || byte == 13 {
                if !pending.isEmpty && !dropping { lines.append(String(decoding: pending, as: UTF8.self)) }
                pending.removeAll(keepingCapacity: true)
                dropping = false
            } else if !dropping {
                if pending.count < maximumLineBytes { pending.append(byte) }
                else { pending.removeAll(keepingCapacity: true); dropping = true; droppedLines += 1 }
            }
        }
        return lines
    }
    public mutating func reset() { pending.removeAll(); dropping = false; droppedLines = 0 }
}

public enum MarauderParser {
    private static let mac = #"([0-9a-f]{2}(?::[0-9a-f]{2}){5})"#
    private static let scan = try! NSRegularExpression(pattern: #"^(?:RSSI:\s*)?(-?\d+)\s+(?:dBm\s+)?Ch:\s*(\d+)\s+(?:BSSID:\s*)?"# + mac + #"\s+ESSID:\s?(.*)$"#, options: [.caseInsensitive])
    private static let list = try! NSRegularExpression(pattern: #"^\[(\d+)\]\[CH:\s*(\d+)\]\s?(.*)$"#, options: [.caseInsensitive])
    private static let relation = try! NSRegularExpression(pattern: #"^(?:\d+:\s*)?(ap|sta):\s*"# + mac + #"\s*->\s*(ap|sta):\s*"# + mac, options: [.caseInsensitive])
    private static let trailingRSSI = try! NSRegularExpression(pattern: #"^(.*?)\s+(-\d{1,3})$"#)
    private static let ansi = try! NSRegularExpression(pattern: #"\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07))"#)
    public static func clean(_ line: String) -> String {
        let stripped = ansi.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
        return String(stripped.unicodeScalars.filter { $0.value >= 32 || $0 == "\t" }).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func groups(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
    public static func parse(_ raw: String) -> ParsedEvent? {
        let line = clean(raw)
        if let g = groups(scan, line), let rssi = Int(g[0]), let channel = Int(g[1]), (1...196).contains(channel), (-127...0).contains(rssi) {
            return .accessPoint(bssid: g[2].uppercased(), ssid: g[3], channel: channel, rssi: rssi)
        }
        if let g = groups(list, line), let index = Int(g[0]), let channel = Int(g[1]) {
            var name = g[2]
            let selected = name.hasSuffix("(selected)")
            if selected {
                name = String(name.dropLast(10))
                while name.last?.isWhitespace == true { name.removeLast() }
            }
            var rssi: Int?
            if let fields = groups(trailingRSSI, name), let value = Int(fields[1]), (-127...0).contains(value) {
                name = fields[0]; rssi = value
            }
            return .listing(APListing(index: index, channel: channel, ssid: name, rssi: rssi, selected: selected))
        }
        if let g = groups(relation, line), g[0].lowercased() != g[2].lowercased() {
            let ap = g[0].lowercased() == "ap" ? g[1] : g[3]
            let station = g[0].lowercased() == "sta" ? g[1] : g[3]
            return .station(ap: ap.uppercased(), mac: station.uppercased())
        }
        if line.hasPrefix("Clearing APs") { return .resetAccessPoints }
        return nil
    }
}

/// BSSID is the physical identity. Name-only firmware list rows are kept separate when ambiguous.
public struct NetworkInventory {
    public private(set) var accessPoints: [String: AccessPoint] = [:]
    private var pendingStations: [String: [Station]] = [:]
    public init() {}
    public mutating func clear() { accessPoints.removeAll(); pendingStations.removeAll() }
    public mutating func invalidateIndices() {
        for key in Array(accessPoints.keys) {
            if key.hasPrefix("index:") { accessPoints.removeValue(forKey: key) }
            else { accessPoints[key]?.index = nil; accessPoints[key]?.selected = false }
        }
    }
    public mutating func consume(_ event: ParsedEvent, at date: Date = Date()) {
        switch event {
        case let .accessPoint(bssid, ssid, channel, rssi):
            var ap = accessPoints[bssid] ?? AccessPoint(id: bssid, bssid: bssid, ssid: ssid, channel: channel)
            ap.ssid = ssid; ap.channel = channel; ap.rssi = rssi; ap.lastSeen = date
            if let stations = pendingStations.removeValue(forKey: bssid) { ap.stations = stations }
            accessPoints[bssid] = ap
        case let .listing(row):
            let candidates = accessPoints.values.filter { $0.bssid != nil && $0.ssid == row.ssid && $0.channel == row.channel }
            // Do not guess BSSIDs for duplicate SSIDs, even when their RSSI happens to match.
            let key = candidates.count == 1 ? candidates[0].id : "index:\(row.index)"
            if candidates.count == 1 { accessPoints.removeValue(forKey: "index:\(row.index)") }
            var ap = accessPoints[key] ?? AccessPoint(id: key, ssid: row.ssid, channel: row.channel)
            ap.index = row.index; ap.selected = row.selected
            if let rssi = row.rssi { ap.rssi = rssi }
            accessPoints[key] = ap // Listing is not a new radio observation: preserve lastSeen.
        case let .station(ap, mac):
            var stations = accessPoints[ap]?.stations ?? pendingStations[ap] ?? []
            if let i = stations.firstIndex(where: { $0.mac == mac }) { stations[i].lastSeen = date }
            else { stations.append(Station(mac: mac, lastSeen: date)) }
            if accessPoints[ap] != nil { accessPoints[ap]?.stations = stations }
            else if pendingStations.count < 2048 { pendingStations[ap] = stations }
        case .resetAccessPoints: clear()
        }
    }
}

public enum CommandValidation {
    public static func validate(_ command: String) throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError("Enter a command first.") }
        guard trimmed.utf8.count <= 512 else { throw ValidationError("Commands must be 512 bytes or fewer.") }
        guard !trimmed.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw ValidationError("Send one command at a time; control characters and newlines are not allowed.")
        }
        guard !trimmed.contains("{") && !trimmed.contains("}") else { throw ValidationError("Fill in the command's placeholders first.") }
        return trimmed
    }
    public static func indices(_ text: String) -> Bool {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { part in
            let p = part.trimmingCharacters(in: .whitespaces)
            return !p.isEmpty && p.allSatisfy(\.isNumber) && Int(p).map { $0 >= 0 && $0 <= 65535 } == true
        }
    }
    public static func mac(_ text: String) -> Bool {
        text.range(of: #"^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$"#, options: .regularExpression) != nil
    }
}
public struct ValidationError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
