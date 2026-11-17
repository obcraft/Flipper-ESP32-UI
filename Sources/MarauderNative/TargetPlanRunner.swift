import Foundation
import MarauderCore

/// A user-started, bounded serial sequence. A fresh BSSID match and verified selection
/// are mandatory before target actions; every timed action ends with an acknowledged stop.
@MainActor
final class TargetPlanRunner {
    private weak var model: AppModel?
    private var task: Task<Void, Never>?
    init(model: AppModel) { self.model = model }
    func start(_ configuration: TargetPlanConfiguration) {
        guard let model, task == nil, model.canSend else { return }
        model.automationFailure = nil
        model.automationRunning = true
        model.automationStatus = "Preparing target discovery…"
        let modern = model.modernFirmware
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run(configuration, modern: modern)
                model.automationStatus = "Completed \(configuration.actions.count) actions. Review the terminal for firmware results."
            } catch is CancellationError {
                model.automationStatus = "Sequence cancelled."
            } catch {
                model.automationStatus = "Stopped: \(error.localizedDescription)"
                model.error = error.localizedDescription
            }
            if model.canSend && model.operation != nil { _ = model.send("stopscan", fromAutomation: true) }
            model.automationRunning = false
            self.task = nil
        }
    }
    func cancel() { task?.cancel() }
    private func check() throws -> AppModel {
        try Task.checkCancellation()
        guard let model, model.canSend else { throw ValidationError("The connection was closed. Reconnect before starting a new sequence.") }
        if let failure = model.automationFailure { throw ValidationError(failure) }
        return model
    }
    private func issue(_ command: String) throws {
        let model = try check()
        guard model.send(command, fromAutomation: true) else { throw ValidationError(model.error ?? "The command could not be sent.") }
    }
    private func wait(timeout: TimeInterval = 6, reason: String, until predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            _ = try check()
            if predicate() { return }
            if Date() >= deadline { throw ValidationError(reason) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    private func readList() async throws {
        let model = try check()
        let before = model.receivedMessageCount
        try issue("list -a")
        try await wait(reason: "No complete AP list was received. Check the terminal and firmware profile.") {
            model.receivedMessageCount > before && Date().timeIntervalSince(model.lastReceivedAt ?? .distantPast) > 0.4
        }
    }
    private func stop() async throws {
        let model = try check()
        // Always issue a stop at operation boundaries; never infer stopping from elapsed time.
        try issue("stopscan")
        try await wait(reason: "No stop acknowledgement was received. Review the terminal before continuing.") { !model.awaitingStopAcknowledgement }
    }
    private func dwell(_ seconds: Int, label: String) async throws {
        let model = try check()
        for remaining in stride(from: seconds, through: 1, by: -1) {
            _ = try check()
            model.automationStatus = "\(label) · \(remaining)s remaining"
            try await Task.sleep(for: .seconds(1))
        }
    }
    private func run(_ configuration: TargetPlanConfiguration, modern: Bool) async throws {
        let model = try check()
        try await stop()
        model.automationStatus = "Discovering the exact BSSID…"
        let discoveryStarted = Date()
        try issue(modern ? "sniffbeacon" : "scanap")
        try await dwell(configuration.discoverySeconds, label: "Discovering \(configuration.target.bssid)")
        try await stop()
        model.automationStatus = "Resolving the firmware index…"
        try await readList()
        guard let target = configuration.target.resolve(in: model.networks), let index = target.index,
              let observed = target.lastSeen, observed >= discoveryStarted else {
            throw ValidationError("The exact BSSID and channel could not be matched to a unique firmware index. No target action was started. Check range, band and duplicate SSIDs.")
        }
        model.selectedNetworks = [target.id]
        model.workflowValues["targets"] = String(index)
        let selected = Set(model.networks.filter(\.selected).compactMap(\.index))
        let toggles = selected.symmetricDifference([index]).sorted()
        if !toggles.isEmpty {
            model.automationStatus = "Selecting the exact access point…"
            let before = model.receivedMessageCount
            try issue("select -a " + toggles.map(String.init).joined(separator: ","))
            try await wait(reason: "No selection response was received.") {
                model.receivedMessageCount > before && Date().timeIntervalSince(model.lastReceivedAt ?? .distantPast) > 0.4
            }
        }
        try await readList()
        let confirmed = Set(model.networks.filter(\.selected).compactMap(\.index))
        guard confirmed == [index], configuration.target.resolve(in: model.networks)?.index == index else {
            throw ValidationError("The firmware did not confirm an exclusive selection of the imported BSSID. No target action was started.")
        }
        // Channel setting is shared by monitor modes and is checked before running them.
        let channelReply = model.receivedMessageCount
        try issue("channel -s \(configuration.target.channel)")
        try await wait(reason: "No channel-setting response was received.") {
            model.receivedMessageCount > channelReply && Date().timeIntervalSince(model.lastReceivedAt ?? .distantPast) > 0.4
        }
        for (position, action) in configuration.actions.enumerated() {
            model.automationStatus = "\(position + 1)/\(configuration.actions.count) · \(action.title)"
            let before = model.receivedMessageCount
            try issue(try action.command(index: index, channel: configuration.target.channel, modern: modern))
            try await wait(reason: "No response to \(action.title). The sequence was stopped.") { model.receivedMessageCount > before }
            if action.timed {
                try await dwell(configuration.secondsPerAction, label: action.title)
                try await stop()
            } else {
                try await wait(reason: "The AP list did not finish arriving.") { Date().timeIntervalSince(model.lastReceivedAt ?? .distantPast) > 0.4 }
            }
        }
    }
}
