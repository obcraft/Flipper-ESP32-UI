import Foundation

public enum TargetAction: String, CaseIterable, Identifiable {
    case inspect, signal, deauthCapture, pmkidCapture, deauthTest, cloneBeacons
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .inspect: return "Read AP selection"
        case .signal: return "Monitor signal"
        case .deauthCapture: return "Listen for deauth frames"
        case .pmkidCapture: return "Capture PMKID"
        case .deauthTest: return "Deauthentication test"
        case .cloneBeacons: return "AP clone beacons"
        }
    }
    public var explanation: String {
        switch self {
        case .inspect: return "Read the selected AP from the firmware list."
        case .signal: return "Monitor the resolved AP index for the chosen duration."
        case .deauthCapture: return "Listen on this channel; this capture also includes other APs on the channel."
        case .pmkidCapture: return "Capture for the selected AP without enabling the active deauthentication option."
        case .deauthTest: return "Transmit deauthentication frames for the selected AP, then stop."
        case .cloneBeacons: return "Transmit beacons using the selected AP's name, then stop."
        }
    }
    public var transmits: Bool { self == .deauthTest || self == .cloneBeacons }
    public var timed: Bool { self != .inspect }
    public func command(index: Int, channel: Int, modern: Bool) throws -> String {
        guard (0...65535).contains(index), (1...14).contains(channel) else { throw ValidationError("The target must resolve to a valid 2.4 GHz AP index.") }
        switch self {
        case .inspect: return "list -a"
        case .signal: return modern ? "foxhunt -w \(index)" : "sigmon"
        case .deauthCapture: return "sniffdeauth"
        case .pmkidCapture: return "sniffpmkid -c \(channel) -l"
        case .deauthTest: return "attack -t deauth"
        case .cloneBeacons: return "attack -t beacon -a"
        }
    }
}

public struct TargetPlanConfiguration {
    public let target: ImportedTarget
    public let actions: [TargetAction]
    public let secondsPerAction: Int
    public let discoverySeconds: Int
    public init(target: ImportedTarget, actions: [TargetAction], secondsPerAction: Int, discoverySeconds: Int = 10, authorizedActiveTests: Bool) throws {
        guard target.supportedByESP32S2 else { throw ValidationError("Channel \(target.channel) is not supported by the ESP32-S2 board. Import the exact 2.4 GHz BSSID instead.") }
        guard !actions.isEmpty else { throw ValidationError("Choose at least one action.") }
        guard Set(actions).count == actions.count else { throw ValidationError("Choose each action once.") }
        guard (5...120).contains(secondsPerAction), (5...30).contains(discoverySeconds) else { throw ValidationError("Use 5–120 seconds per action and 5–30 seconds for discovery.") }
        guard !actions.contains(where: \.transmits) || authorizedActiveTests else { throw ValidationError("Confirm permission for active tests on this network before starting.") }
        self.target = target; self.actions = actions; self.secondsPerAction = secondsPerAction; self.discoverySeconds = discoverySeconds
    }
}
