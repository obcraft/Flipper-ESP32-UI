import Foundation

public struct WorkflowField: Identifiable {
    public var id: String
    public var label: String
    public var placeholder: String
    public var kind: Kind
    public enum Kind { case indices, mac, name, count }
    public func isValid(_ value: String) -> Bool {
        switch kind {
        case .indices: return CommandValidation.indices(value)
        case .mac: return CommandValidation.mac(value)
        case .name: return !value.isEmpty && value.utf8.count <= 32 && !value.contains("\"") && !value.contains("\\") && !value.contains(where: \.isNewline)
        case .count: return Int(value).map { (1...100).contains($0) } == true
        }
    }
}
public struct WorkflowStep: Identifiable {
    public var id: Int
    public var title: String
    public var command: String
    public var guidance: String
}
public struct Workflow: Identifiable {
    public var id: String
    public var name: String
    public var symbol: String
    public var summary: String
    public var fields: [WorkflowField]
    public var steps: [WorkflowStep]
    public var activeTransmission: Bool
    public func render(_ step: WorkflowStep, values: [String: String], modern: Bool) throws -> String {
        var command = step.command.replacingOccurrences(of: "{scanAP}", with: modern ? "sniffbeacon" : "scanap")
            .replacingOccurrences(of: "{scanSTA}", with: modern ? "scanall" : "scansta")
            .replacingOccurrences(of: "{wardrive}", with: modern ? "wardrive" : "wardrive -s")
        if modern && command == "sigmon" {
            guard let value = values["targets"]?.trimmingCharacters(in: .whitespaces),
                  let index = Int(value), (0...65535).contains(index) else {
                throw ValidationError("Current firmware signal monitoring requires exactly one AP index.")
            }
            command = "foxhunt -w \(index)"
        }
        for field in fields where command.contains("{\(field.id)}") {
            let value = (values[field.id] ?? "").trimmingCharacters(in: .whitespaces)
            guard field.isValid(value) else { throw ValidationError("Enter a valid \(field.label.lowercased()).") }
            command = command.replacingOccurrences(of: "{\(field.id)}", with: value)
        }
        return try CommandValidation.validate(command)
    }
    public static let catalog: [Workflow] = {
        let targets = WorkflowField(id: "targets", label: "AP indices", placeholder: "0,1", kind: .indices)
        let stations = WorkflowField(id: "stations", label: "Station indices", placeholder: "Use list -c output", kind: .indices)
        let scan: [(String, String, String)] = [
            ("Discover networks", "{scanAP}", "Let the scan collect networks, then send the next step to stop it."),
            ("Stop scanning", "stopscan", "Wait for the device to report that scanning stopped."),
            ("Read AP indices", "list -a", "Use the returned indices. Select a network in Networks, or enter indices below."),
            ("Select APs", "select -a {targets}", "Selection may toggle on some firmware versions. Check the next list before continuing."),
            ("Verify selection", "list -a", "Confirm the intended APs are marked selected before continuing.")
        ]
        func make(_ id: String, _ name: String, _ symbol: String, _ summary: String, _ fields: [WorkflowField], _ commands: [(String, String, String)], _ active: Bool = false) -> Workflow {
            Workflow(id: id, name: name, symbol: symbol, summary: summary, fields: fields, steps: commands.enumerated().map { WorkflowStep(id: $0.offset, title: $0.element.0, command: $0.element.1, guidance: $0.element.2) }, activeTransmission: active)
        }
        return [
            make("survey", "Network survey", "wifi", "Discover nearby access points and read their device indices.", [], Array(scan.prefix(3))),
            make("station-survey", "Discover stations", "laptopcomputer", "Find client devices and see which access points they communicate with.", [], Array(scan.prefix(3)) + [("Discover stations", "{scanSTA}", "Watch Stations for new MAC addresses. Leave discovery running long enough for clients to send traffic."), ("Stop discovery", "stopscan", "Wait for the stopping message before requesting the list."), ("Read station indices", "list -c", "The terminal groups clients under access points. These are the indices used in station workflows.")]),
            make("ap-list", "List access points", "list.bullet", "Refresh network indices and selected states from the device.", [], [("Read access points", "list -a", "Compare the firmware indices and selected markers with Networks. This reads existing results; it does not start a scan.")]),
            make("station-list", "List stations", "person.2", "Read the device's current client list and station indices.", [], [("Read stations", "list -c", "Read the terminal for station indices grouped under APs. An empty list means no clients have been discovered yet.")]),
            make("deauth-sniff", "Observe deauth traffic", "waveform.path.ecg", "Listen for deauthentication frames and inspect their output.", [], [("Start listening", "sniffdeauth", "Watch the terminal for received frames. No output may simply mean no deauthentication frames are present."), ("Stop listening", "stopscan", "Wait for the stop response. Export the terminal if you want to keep this observation.")]),
            make("pmkid-listen", "Listen for PMKID", "key.horizontal", "Start PMKID capture without enabling the active deauthentication option.", [], [("Start capture", "sniffpmkid", "Observe the terminal. A capture depends on compatible traffic; silence is not a successful capture."), ("Stop capture", "stopscan", "Review the terminal and any files saved by your firmware. The app does not automatically download capture files.")]),
            make("wardrive", "Wardrive", "location", "Collect location-aware Wi-Fi observations with supported GPS and storage hardware.", [], [("Start wardrive", "{wardrive}", "Check the firmware output for GPS fix and storage status. Stop if required hardware is missing."), ("Stop wardrive", "stopscan", "Wait for the stop response. Retrieve recorded files using your board's supported storage workflow.")]),
            make("signal", "Signal monitor", "waveform.path", "Follow signal levels from selected access points.", [targets], scan + [("Monitor signal", "sigmon", "Current firmware uses foxhunt with one AP index; classic firmware uses sigmon. Use Stop when finished.")]),
            make("pmkid", "Active PMKID capture", "waveform.path.ecg", "Capture PMKID traffic for selected access points.", [targets], scan + [("Start capture", "sniffpmkid -d -l", "Use Stop to finish capture.")], true),
            make("random-list", "Random beacon list", "list.bullet.rectangle", "Generate a list of names and transmit its beacons.", [.init(id: "count", label: "SSID count", placeholder: "10", kind: .count)], [("Generate names", "ssid -a -g {count}", "Inspect the list before transmitting."), ("Read names", "list -s", "Verify the generated names."), ("Transmit beacons", "attack -t beacon -l", "Use Stop when finished.")], true),
            make("random", "Random beacons", "antenna.radiowaves.left.and.right", "Transmit automatically generated network names.", [], [("Transmit beacons", "attack -t beacon -r", "Use Stop when finished.")], true),
            make("custom", "Custom beacon list", "text.badge.plus", "Add a network name to the firmware's SSID list.", [.init(id: "name", label: "Network name", placeholder: "Lab network", kind: .name)], [("Add name", "ssid -a -n \"{name}\"", "This adds to the existing firmware list."), ("Inspect list", "list -s", "Verify all names in the list."), ("Transmit beacons", "attack -t beacon -l", "Use Stop when finished.")], true),
            make("clone", "AP clone beacons", "square.on.square", "Transmit beacon names based on selected access points.", [targets], scan + [("Transmit cloned beacons", "attack -t beacon -a", "Use Stop when finished.")], true),
            make("deauth", "Deauthentication", "wifi.slash", "Send deauthentication frames for selected access points.", [targets], scan + [("Start deauthentication", "attack -t deauth", "Use Stop when finished.")], true),
            make("targeted", "Station deauthentication", "laptopcomputer", "Use AP and station indices to address specific clients.", [targets, stations], scan + [("Discover stations", "{scanSTA}", "Let stations appear, then stop the scan."), ("Stop station scan", "stopscan", "Wait for scanning to stop."), ("Read station indices", "list -c", "Use the list indices, not the scan event numbers."), ("Select stations", "select -c {stations}", "Verify station selection in the next step."), ("Verify stations", "list -c", "Check selected stations."), ("Start deauthentication", "attack -t deauth -c", "Use Stop when finished.")], true),
            make("manual", "Addressed deauthentication", "arrow.left.arrow.right", "Set source and destination MAC addresses explicitly.", [.init(id: "source", label: "Source MAC", placeholder: "00:11:22:33:44:55", kind: .mac), .init(id: "destination", label: "Destination MAC", placeholder: "AA:BB:CC:DD:EE:FF", kind: .mac)], [("Send addressed frames", "attack -t deauth -s {source} -d {destination}", "Use Stop when finished.")], true)
        ]
    }()
}
