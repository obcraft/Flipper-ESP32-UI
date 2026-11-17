import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MarauderCore

struct TerminalLine: Identifiable {
    let id: Int
    let date: Date
    let text: String
    let kind: Kind
    enum Kind { case received, command, info, error }
}

enum Destination: String, CaseIterable, Identifiable {
    case networks = "Networks", stations = "Stations", workflows = "Workflows", connection = "Connection"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .networks: return "wifi"; case .stations: return "laptopcomputer"; case .workflows: return "square.stack.3d.up"; case .connection: return "cable.connector" }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var destination: Destination? = .networks
    @Published var devices: [SerialDevice] = []
    @Published var selectedPort = ""
    @Published var baud = 115200
    @Published var lineEnding = "\n"
    @Published var connected = false
    @Published var demo = false
    @Published var receivedBytes = 0
    @Published var transmittedBytes = 0
    @Published var status = "Ready to connect"
    @Published var error: String?
    @Published var networks: [AccessPoint] = []
    @Published var selectedNetworks = Set<String>()
    @Published var watchedBSSIDs = Set<String>()
    @Published var terminal: [TerminalLine] = []
    @Published var history: [String] = []
    @Published var command = ""
    @Published var search = ""
    @Published var sort = "Signal"
    @Published var detailed = true
    @Published var followTerminal = true
    @Published var terminalSearch = ""
    @Published var modernFirmware = true {
        didSet { UserDefaults.standard.set(modernFirmware, forKey: "modernFirmware") }
    }
    @Published var workflowDetailVisible = false
    @Published var importedTarget: ImportedTarget?
    @Published var targetPaste = ""
    @Published var targetActions: [TargetAction] = [.inspect, .signal]
    @Published var actionDuration = 15
    @Published var authorizedTargetTests = false
    @Published var automationRunning = false
    @Published var automationStatus = ""
    var automationFailure: String?
    var receivedMessageCount = 0
    var lastReceivedAt: Date?
    var awaitingStopAcknowledgement: Bool { stopPending }
    lazy var automation = TargetPlanRunner(model: self)
    private var demoSelectedIndices = Set<Int>()
    @Published var selectedWorkflow = Workflow.catalog[0].id
    @Published var workflowValues: [String: String] = [:]
    @Published var completedSteps = Set<Int>()
    @Published var workflowCursor = 0
    @Published var operation: String?
    @Published var sessionStarted: Date?
    private let port = SerialPort()
    private var inventory = NetworkInventory()
    private var framer = LineFramer()
    private var timer: Timer?
    private var ticks = 0
    private var sequence = 0
    private var historyIndex = -1
    private var draft = ""
    private var stopPending = false
    private var stopRequestedAt: Date?
    private var connectTime: Date?
    private var probeStartBytes = 0
    var canSend: Bool { connected || demo }
    var profileName: String { modernFirmware ? "Current firmware" : "Classic firmware" }
    var scanAP: String { modernFirmware ? "sniffbeacon" : "scanap" }
    var scanStations: String { modernFirmware ? "scanall" : "scansta" }
    var workflow: Workflow { Workflow.catalog.first { $0.id == selectedWorkflow } ?? Workflow.catalog[0] }
    var selectedAP: AccessPoint? { networks.first { selectedNetworks.contains($0.id) } }
    var stationCount: Int { Set(networks.flatMap { $0.stations.map(\.mac) }).count }
    var watchedNetworks: [AccessPoint] {
        networks.filter { watchedBSSIDs.contains($0.id) }.sorted { a, b in
            let order = a.displayName.localizedStandardCompare(b.displayName)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }
    var filteredNetworks: [AccessPoint] {
        networks.filter { ap in
            search.isEmpty || ap.displayName.localizedCaseInsensitiveContains(search) || (ap.bssid ?? "").localizedCaseInsensitiveContains(search) || ap.stations.contains { $0.mac.localizedCaseInsensitiveContains(search) }
        }.sorted { a,b in
            switch sort {
            case "Name": return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            case "Channel": return a.channel == b.channel ? a.id < b.id : a.channel < b.channel
            case "Stations": return a.stations.count == b.stations.count ? a.id < b.id : a.stations.count > b.stations.count
            default: return a.rssi == b.rssi ? a.id < b.id : (a.rssi ?? -999) > (b.rssi ?? -999)
            }
        }
    }
    init() {
        history = UserDefaults.standard.stringArray(forKey: "commandHistory") ?? []
        if UserDefaults.standard.object(forKey: "modernFirmware") != nil { modernFirmware = UserDefaults.standard.bool(forKey: "modernFirmware") }
        refreshPorts()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }
    func refreshPorts() {
        let found = SerialDevice.available()
        if devices != found { devices = found }
        if !connected && !devices.contains(where: { $0.path == selectedPort }) { selectedPort = devices.first?.path ?? "" }
    }
    func connect() {
        guard !automationRunning else { error = "Stop the sequence before changing connections."; return }
        guard !selectedPort.isEmpty else { error = "No USB serial port found. Connect the Flipper and start GPIO → USB-UART Bridge."; return }
        if demo { endDemo() }
        do {
            try port.open(path: selectedPort, baud: baud)
            resetSession()
            connected = true; connectTime = nil; sessionStarted = Date(); status = "USB connected · ready for commands"; error = nil
            append("Opened \(selectedPort) at \(baud) baud · 8N1", .info)
            append("Connection open. Use Check connection or send help to read the supported commands.", .info)
        } catch { self.error = error.localizedDescription; append(error.localizedDescription, .error) }
    }
    func disconnect() {
        automation.cancel()
        port.close(); connected = false; operation = nil; stopPending = false; connectTime = nil
        framer.reset(); status = "Disconnected"
        append("Serial connection closed. USB-UART Bridge is controlled on your Flipper.", .info)
    }
    func shutdown() { automation.cancel(); if automationRunning { try? port.send("stopscan") }; timer?.invalidate(); port.close() }
    private func resetSession() {
        inventory.clear(); networks = []; selectedNetworks = []; terminal = []; framer.reset()
        watchedBSSIDs.removeAll()
        receivedBytes = 0; transmittedBytes = 0; receivedMessageCount = 0; lastReceivedAt = nil; demoSelectedIndices = []; operation = nil; stopPending = false
        completedSteps = []; workflowCursor = 0; workflowValues = [:]
    }
    @discardableResult func send(_ raw: String, fromAutomation: Bool = false) -> Bool {
        do {
            let value = try CommandValidation.validate(raw)
            if automationRunning && !fromAutomation {
                if value == "stopscan" { automation.cancel() }
                else { throw ValidationError("Stop the automatic sequence before sending a separate command.") }
            }
            guard canSend else { throw ValidationError("Connect your Flipper, or open the demo, before sending commands.") }
            let startsOperation = value.hasPrefix("sniff") || value.hasPrefix("scan") || value.hasPrefix("attack ") || value.hasPrefix("wardrive") || value == "sigmon" || value.hasPrefix("foxhunt ")
            if startsOperation && operation != nil { throw ValidationError("Stop the current operation and wait for its response before starting another.") }
            if demo { append(value, .command); simulate(value) }
            else {
                try port.send(value, lineEnding: lineEnding)
                transmittedBytes += value.utf8.count + lineEnding.utf8.count
                append(value, .command)
            }
            if value == "help" && !demo { connectTime = Date(); probeStartBytes = receivedBytes }
            if value == "list -a" { inventory.invalidateIndices(); networks = Array(inventory.accessPoints.values); if demo { demoList() } }
            if startsOperation { operation = value }
            if value == "stopscan" {
                if demo { operation = nil; stopPending = false }
                else { stopPending = true; stopRequestedAt = Date() }
            }
            history.removeAll { $0 == value }; history.insert(value, at: 0)
            history = Array(history.prefix(50)); UserDefaults.standard.set(history, forKey: "commandHistory")
            historyIndex = -1; error = nil
            return true
        } catch { self.error = error.localizedDescription; append(error.localizedDescription, .error); return false }
    }
    func sendInput() { if send(command) { command = "" } }
    func historyPrevious() {
        guard !history.isEmpty else { return }
        if historyIndex == -1 { draft = command }
        historyIndex = min(historyIndex + 1, history.count - 1); command = history[historyIndex]
    }
    func historyNext() {
        guard historyIndex >= 0 else { return }
        historyIndex -= 1; command = historyIndex >= 0 ? history[historyIndex] : draft
    }
    func clearHistory() { history = []; historyIndex = -1; UserDefaults.standard.removeObject(forKey: "commandHistory") }
    func clearTerminal() { terminal.removeAll() }
    func clearNetworks() { inventory.clear(); networks.removeAll(); selectedNetworks.removeAll() }
    func useSelectedIndices() {
        let selected = networks.filter { selectedNetworks.contains($0.id) }
        guard !selected.isEmpty, selected.allSatisfy({ $0.index != nil }) else {
            error = "Request List APs first. The firmware must report indices before these networks can be selected."; return
        }
        workflowValues["targets"] = selected.compactMap(\.index).sorted().map(String.init).joined(separator: ",")
    }
    func selectOnDevice() {
        useSelectedIndices()
        guard let indices = workflowValues["targets"], !selectedNetworks.isEmpty,
              networks.filter({ selectedNetworks.contains($0.id) }).allSatisfy({ $0.index != nil }) else { return }
        _ = send("select -a \(indices)")
    }
    func changeWorkflow() { completedSteps = []; workflowCursor = 0 }
    func sendWorkflowStep(_ step: WorkflowStep) {
        do {
            let command = try workflow.render(step, values: workflowValues, modern: modernFirmware)
            if send(command) { completedSteps.insert(step.id); workflowCursor = min(step.id + 1, workflow.steps.count) }
        } catch { self.error = error.localizedDescription }
    }
    func acknowledgeStopped() {
        // Explicit user verification for firmware that does not emit a recognized stop message.
        operation = nil; stopPending = false
        append("Operation marked stopped after reviewing device output.", .info)
    }
    private func poll() {
        ticks += 1
        if ticks % 40 == 0 {
            refreshPorts()
            if connected && !FileManager.default.fileExists(atPath: selectedPort) {
                disconnect(); error = "Flipper unplugged. Reconnect it and re-enable USB-UART Bridge."; return
            }
        }
        if demo && ticks % 40 == 0 && operation != nil { demoScan() }
        guard connected else { return }
        do {
            let bytes = try port.readAvailable()
            if !bytes.isEmpty {
                receivedBytes += bytes.count
                for line in framer.append(bytes) { receive(line) }
                networks = Array(inventory.accessPoints.values)
            }
            if let started = connectTime, Date().timeIntervalSince(started) > 5, receivedBytes == probeStartBytes {
                status = "Port open · no device response"
                error = "No Marauder response. Check USB channel 0 and 115200 baud on the Flipper, and make sure the Wi-Fi board is attached. Close qFlipper if it is using the port."
                connectTime = nil
            }
            if stopPending, let requested = stopRequestedAt, Date().timeIntervalSince(requested) > 4 {
                error = "Stop sent, but no recognized acknowledgement. Check the terminal; use “Mark stopped” only once the device has stopped."
                stopRequestedAt = nil
            }
        } catch { disconnect(); self.error = error.localizedDescription; append(error.localizedDescription, .error) }
    }
    private func receive(_ raw: String) {
        let line = MarauderParser.clean(raw)
        guard !line.isEmpty else { return }
        receivedMessageCount += 1; lastReceivedAt = Date()
        append(line, .received)
        if automationRunning && (line.lowercased().hasPrefix("error") || line.lowercased().hasPrefix("invalid") || line.lowercased().hasPrefix("unknown command") || line.lowercased().hasPrefix("failed") || line.lowercased().contains("command not found") || line.lowercased().hasPrefix("you don't have any targets")) {
            automationFailure = "The firmware rejected an operation: \(line)"
        }
        let lower = line.lowercased()
        if lower.contains("guru meditation") || lower.contains("panic'ed") {
            status = "ESP32 firmware crashed"; operation = nil; automationFailure = "The ESP32 firmware crashed."
            error = "The ESP32 reported a firmware crash. Wait for its boot message before sending another command. The serial connection remains open."
        }
        if lower == "rebooting..." || lower.hasPrefix("esp-rom:") {
            status = "ESP32 restarting"; operation = nil; if automationRunning { automationFailure = "The ESP32 restarted during the sequence." }
            inventory.clear(); networks = []; selectedNetworks = []; workflowValues = [:]; completedSteps = []; workflowCursor = 0
        }
        if lower.contains("============ commands") { status = "Marauder responding"; connectTime = nil }
        if lower.contains("marauder") { status = "Marauder responding"; connectTime = nil }
        if let event = MarauderParser.parse(line) { inventory.consume(event); if connected { status = "Receiving device data" } }
        if stopPending && (lower.contains("stopped") || lower.contains("stopping") || lower == "stopscan" || lower.contains("stop scan")) {
            operation = nil; stopPending = false; stopRequestedAt = nil; error = nil
        }
        if lower.contains("unknown command") || lower.contains("invalid command") || lower.contains("command not found") {
            operation = nil; error = "This firmware did not recognize the command. Read Help or change the firmware profile in Connection."
        }
    }
    private func append(_ text: String, _ kind: TerminalLine.Kind) {
        sequence += 1; terminal.append(TerminalLine(id: sequence, date: Date(), text: text, kind: kind))
        if terminal.count > 2000 { terminal.removeFirst(terminal.count - 2000) }
    }
    func startDemo() {
        guard !connected && !automationRunning else { return }
        resetSession(); demo = true; sessionStarted = Date(); status = "Demo · simulated data"; error = nil
        append("Demo session. No USB port is open and no radio commands are transmitted.", .info)
        demoScan(); demoList()
        for index in [0, 0, 1, 3, 3, 3] {
            let mac = String(format: "02:DD:00:00:%02X:%02X", index, sequence % 255)
            receive("1: ap: \(demoMAC(index)) -> sta: \(mac)")
        }
        networks = Array(inventory.accessPoints.values)
    }
    func endDemo() { automation.cancel(); demo = false; operation = nil; resetSession(); status = "Ready to connect" }
    private let demoNames = ["Studio", "Workshop", "Guest network", "Lab 2.4 GHz", "Studio", "", "Garden", "Sensor network"]
    private let demoChannels = [1, 6, 11, 6, 1, 11, 3, 9]
    private func demoMAC(_ index: Int) -> String { String(format: "02:4D:41:52:41:%02X", index) }
    private func demoScan() {
        for i in demoNames.indices {
            let signal = -34 - i * 6 + (ticks / 40 % 5)
            receive("\(signal) Ch: \(demoChannels[i]) \(demoMAC(i)) ESSID: \(demoNames[i])")
        }
        networks = Array(inventory.accessPoints.values)
    }
    private func demoList() {
        for i in demoNames.indices { receive("[\(i)][CH:\(demoChannels[i])] \(demoNames[i]) \(-34-i*6)\(demoSelectedIndices.contains(i) ? " (selected)" : "")") }
        networks = Array(inventory.accessPoints.values)
    }
    private func simulate(_ command: String) {
        if command.hasPrefix("select -a ") {
            for field in command.dropFirst(10).split(separator: ",") {
                if let index = Int(field.trimmingCharacters(in: .whitespaces)) {
                    if demoSelectedIndices.contains(index) { demoSelectedIndices.remove(index) }
                    else { demoSelectedIndices.insert(index) }
                }
            }
            receive("Demo selection updated."); return
        }
        switch command {
        case "info": receive("ESP32 Marauder · demonstration firmware · no hardware connected")
        case "help": receive("Demo: sniffbeacon, scanall, list -a, stopscan. Other commands are recorded only.")
        case "sniffbeacon", "scanap", "scanall", "scansta": demoScan()
        case "list -a": break // Populate after index invalidation.
        case "stopscan": receive("Stopped scanning.")
        default: receive("Demo recorded command. No hardware action performed.")
        }
    }
    func exportTerminal() {
        let text = terminal.map { "\($0.date.ISO8601Format()) \($0.kind == .command ? "> " : "")\($0.text)" }.joined(separator: "\n")
        save(Data(text.utf8), name: "marauder-session.txt", type: .plainText)
    }
    func exportNetworks() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        do { save(try encoder.encode(networks), name: "marauder-networks.json", type: .json) }
        catch { self.error = error.localizedDescription }
    }
    private func save(_ data: Data, name: String, type: UTType) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.allowedContentTypes = [type]
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic) } catch { self.error = error.localizedDescription }
        }
    }
}
