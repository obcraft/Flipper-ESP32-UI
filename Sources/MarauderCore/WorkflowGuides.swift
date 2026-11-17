import Foundation

public enum WorkflowCategory: String, CaseIterable {
    case discovery = "Discover & inspect"
    case monitoring = "Listen & monitor"
    case transmission = "Active radio tests"
}

public struct WorkflowGuide {
    public var start: String
    public var expected: String
    public var next: String
    public var nextWorkflow: String?
}

public extension Workflow {
    var category: WorkflowCategory {
        if activeTransmission { return .transmission }
        if ["deauth-sniff", "pmkid-listen", "signal", "wardrive"].contains(id) { return .monitoring }
        return .discovery
    }
    var guide: WorkflowGuide {
        switch id {
        case "survey": return .init(start: "Connect the Flipper bridge, then start discovery. No network selection is needed.", expected: "Networks appear with a channel, MAC address and signal level. Stop discovery before reading the device indices.", next: "Select a network in Networks to inspect it, or discover its associated stations.", nextWorkflow: "station-survey")
        case "station-survey": return .init(start: "Begin with an AP discovery so the app can associate clients with known networks.", expected: "Stations shows client MAC addresses grouped by access point. Quiet clients may not appear immediately.", next: "Read List stations for the exact device indices, or export the network snapshot.", nextWorkflow: "station-list")
        case "ap-list": return .init(start: "Run a network survey first and stop scanning. This reads the device's existing list.", expected: "AP indices and selected markers appear in the terminal and the network table.", next: "Choose an AP in Networks and use it in a monitoring workflow.", nextWorkflow: "signal")
        case "station-list": return .init(start: "Discover stations first, then stop the discovery operation.", expected: "The terminal lists client MAC addresses and indices beneath their access points.", next: "Use the list indices when a workflow asks for a station. Scan counters are not station indices.", nextWorkflow: nil)
        case "deauth-sniff": return .init(start: "Stop other scans, then begin listening. This workflow observes frames rather than sending deauthentication requests.", expected: "Received deauthentication frames appear in the terminal. An empty log can mean no relevant traffic was observed.", next: "Stop listening, review the output, and export it if you want a record.", nextWorkflow: nil)
        case "pmkid-listen": return .init(start: "Connect the device and stop other operations. Capture availability depends on your firmware and the observed traffic.", expected: "The firmware reports relevant capture events. A quiet terminal does not prove that a capture succeeded.", next: "Stop capture, review the terminal, and retrieve any capture file through your board's supported storage path.", nextWorkflow: nil)
        case "wardrive": return .init(start: "Use a board with supported GPS and storage. Your firmware must report a GPS fix and usable storage.", expected: "Location-aware observations and recording status appear in the firmware output.", next: "Stop recording before disconnecting and retrieve the files from the board's storage.", nextWorkflow: nil)
        case "signal": return .init(start: "Discover and select an AP. Current firmware requires one AP index for signal monitoring.", expected: "Signal readings arrive in the terminal. Their availability and rate depend on the selected firmware.", next: "Compare readings as you change position, then stop monitoring before starting another operation.", nextWorkflow: nil)
        case "pmkid": return .init(start: "Discover the intended AP and verify its index and selected marker. This version enables active deauthentication.", expected: "The firmware reports capture activity for selected APs. A sent command alone is not evidence of a successful capture.", next: "Stop the capture and inspect the firmware output and stored capture files.", nextWorkflow: nil)
        case "random-list": return .init(start: "Choose how many SSIDs to generate. Review the firmware list before starting transmission.", expected: "The generated list is printed first, followed by the beacon operation's status.", next: "Stop transmission when finished. The generated list remains on the device until you clear or replace it.", nextWorkflow: nil)
        case "random": return .init(start: "Connect the device and stop other operations. This workflow transmits automatically generated network names.", expected: "The terminal reports the beacon operation starting. Inspect the result with a separate Wi-Fi observer.", next: "Use the global Stop button when the observation is complete.", nextWorkflow: nil)
        case "custom": return .init(start: "Enter a network name of up to 32 UTF-8 bytes. It will be added to the device's existing SSID list.", expected: "The list step lets you verify all names before starting beacon transmission.", next: "Stop the operation when finished and review which names remain in the firmware list.", nextWorkflow: nil)
        case "clone": return .init(start: "Discover and select the intended access points. Verify the selected markers in the device list.", expected: "The device reports a beacon operation using the selected AP names.", next: "Stop transmission before changing the selected networks or starting another workflow.", nextWorkflow: nil)
        case "deauth", "targeted": return .init(start: "Discover the intended AP and verify its selection. Station-specific testing also needs confirmed client indices.", expected: "The terminal reports the operation. Verify effects separately; the app does not claim that a client disconnected.", next: "Stop the operation when the test is complete, then inspect whether the intended devices recovered.", nextWorkflow: nil)
        default: return .init(start: "Enter both MAC addresses and check the full command preview before sending it.", expected: "The terminal reports the firmware response. Sent means written to the serial connection, not that the operation succeeded.", next: "Stop the operation when finished and review the device response.", nextWorkflow: nil)
        }
    }
}
