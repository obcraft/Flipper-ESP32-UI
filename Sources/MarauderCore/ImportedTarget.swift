import Foundation

public struct ImportedTarget: Identifiable, Equatable, Codable {
    public var id: String { bssid }
    public let name: String
    public let bssid: String
    public let channel: Int
    public let width: Int?
    public let rssi: Int?
    public let country: String?
    public let phy: String?
    public var supportedByESP32S2: Bool { (1...14).contains(channel) }
    public var band: String { supportedByESP32S2 ? "2.4 GHz" : "5 GHz / unsupported" }
    public static func parse(_ text: String) throws -> ImportedTarget {
        guard text.utf8.count <= 16_384 else { throw ValidationError("Paste one network record of up to 16 KB.") }
        func match(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(result.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        let bssidPattern = #"\bbssid\s*=\s*([0-9a-f]{2}(?::[0-9a-f]{2}){5})(?=\s|,|$)"#
        let matches = try NSRegularExpression(pattern: bssidPattern, options: .caseInsensitive)
            .numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches == 1, let bssid = match(bssidPattern) else { throw ValidationError("Paste exactly one network with a valid bssid=AA:BB:CC:DD:EE:FF field.") }
        guard let channelText = match(#"\bchannel\s*=\s*\[?\s*(\d+)"#),
              let channel = Int(channelText), (1...196).contains(channel) else { throw ValidationError("A valid channel is required, for example channel=[6, width=20].") }
        let name = match(#"^\s*['"‘“](.*?)['"’”]\s*(?:\{|,)"#) ?? match(#"\bssid\s*=\s*['"‘“](.*?)['"’”](?=\s|,|$)"#) ?? ""
        guard name.utf8.count <= 32 else { throw ValidationError("The network name exceeds the 32-byte Wi-Fi SSID limit.") }
        guard let firstByte = UInt8(bssid.prefix(2), radix: 16), firstByte & 1 == 0 else { throw ValidationError("An access-point BSSID must be a unicast MAC address.") }
        return ImportedTarget(name: name, bssid: bssid.uppercased(), channel: channel,
                              width: match(#"\bwidth\s*=\s*(\d+)"#).flatMap(Int.init),
                              rssi: match(#"\brssi\s*=\s*(-?\d+)"#).flatMap(Int.init),
                              country: match(#"\bcc\s*=\s*([a-z]{2})"#)?.uppercased(),
                              phy: match(#"\btype\s*=\s*([^,\s]+)"#))
    }
    public func resolve(in networks: [AccessPoint]) -> AccessPoint? {
        guard supportedByESP32S2 else { return nil }
        return networks.first { $0.bssid?.caseInsensitiveCompare(bssid) == .orderedSame && $0.channel == channel }
    }
}
