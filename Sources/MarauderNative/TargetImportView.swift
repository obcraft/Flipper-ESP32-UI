import SwiftUI
import AppKit
import MarauderCore

struct TargetImportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    private var parsed: ImportedTarget? { try? ImportedTarget.parse(input) }
    private var parsingError: String? {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do { _ = try ImportedTarget.parse(input); return nil } catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Paste a network", subtitle: "Import a macOS Wi-Fi record. The exact BSSID identifies your target.")
            HStack {
                Text("NETWORK RECORD").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Button("Paste from clipboard", systemImage: "doc.on.clipboard") {
                    if let value = NSPasteboard.general.string(forType: .string) { input = value }
                }
            }
            TextEditor(text: $input).font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 145).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            Text("Example: 'Workshop' {length = 8}, bssid=02:4D:41:52:41:01, channel=[6, width=20], cc=NL, type=11n, rssi=-40")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            if let target = parsed {
                VStack(alignment: .leading, spacing: 10) {
                    Text(target.name.isEmpty ? "Hidden network" : target.name).font(.title3.weight(.semibold))
                    Text(target.bssid).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    HStack(spacing: 18) {
                        Text("Channel \(target.channel)")
                        if let width = target.width { Text("\(width) MHz") }
                        if let rssi = target.rssi { Text("\(rssi) dBm") }
                        if let phy = target.phy { Text(phy) }
                    }.font(.callout).foregroundStyle(.secondary)
                    if !target.supportedByESP32S2 {
                        Label("Your ESP32-S2 board supports 2.4 GHz only. This record can be saved, but actions on channel \(target.channel) are disabled. Import the network’s 2.4 GHz BSSID instead.", systemImage: "wifi.exclamationmark")
                            .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            } else if let parsingError {
                Label(parsingError, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout)
            } else {
                Text("Name, BSSID, channel, width, country, Wi-Fi type and signal are read automatically. Importing does not start a scan or transmit commands.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use this network") {
                    guard let target = parsed else { return }
                    model.targetPaste = input; model.importedTarget = target
                    model.authorizedTargetTests = false; model.automationStatus = ""
                    model.workflowDetailVisible = false
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(parsed == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 680, height: 560)
            .onAppear { input = model.targetPaste }
    }
}

struct TargetPlanView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let target = model.importedTarget {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: "scope").font(.title2).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(target.name.isEmpty ? "Imported hidden network" : target.name).font(.title3.weight(.semibold))
                        Text("\(target.bssid) · channel \(target.channel) · \(target.band)")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button { model.importedTarget = nil; model.authorizedTargetTests = false } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless).disabled(model.automationRunning).help("Remove imported target")
                }
                if !target.supportedByESP32S2 {
                    Label("This channel cannot be used by your ESP32-S2 board. Paste the exact 2.4 GHz BSSID; a matching network name is not enough.", systemImage: "wifi.exclamationmark")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Text("Choose actions in execution order. The app first discovers the exact MAC address, reads its index and verifies that only this AP is selected. It stops between timed actions.")
                    .font(.callout).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(TargetAction.allCases) { action in
                        Toggle(isOn: Binding(get: { model.targetActions.contains(action) }, set: { selected in
                            if selected { model.targetActions.append(action) } else { model.targetActions.removeAll { $0 == action } }
                        })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(action.title).font(.callout.weight(.medium))
                                Text(action.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }.toggleStyle(.checkbox).disabled(model.automationRunning)
                    }
                }
                if !model.targetActions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EXECUTION ORDER").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                        ForEach(Array(model.targetActions.enumerated()), id: \.element.id) { position, action in
                            HStack(spacing: 10) {
                                Text("\(position + 1)").font(.caption.monospacedDigit()).foregroundStyle(.orange).frame(width: 20)
                                Text(action.title).font(.callout)
                                Spacer()
                                Button { model.targetActions.swapAt(position, position - 1) } label: { Image(systemName: "arrow.up") }.disabled(position == 0 || model.automationRunning).help("Move earlier")
                                Button { model.targetActions.swapAt(position, position + 1) } label: { Image(systemName: "arrow.down") }.disabled(position == model.targetActions.count - 1 || model.automationRunning).help("Move later")
                            }.buttonStyle(.borderless)
                        }
                    }.padding(12).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Stepper("\(model.actionDuration) seconds per timed action", value: $model.actionDuration, in: 5...120, step: 5)
                        .fixedSize().disabled(model.automationRunning)
                    Spacer()
                    Text("10 seconds initial discovery").font(.caption).foregroundStyle(.secondary)
                }
                if model.targetActions.contains(where: \.transmits) {
                    Toggle("I have permission to run active tests on this network.", isOn: $model.authorizedTargetTests)
                        .toggleStyle(.checkbox).font(.callout).disabled(model.automationRunning)
                }
                HStack {
                    if model.automationRunning { ProgressView().controlSize(.small) }
                    Text(model.automationStatus.isEmpty ? "Ready to prepare a sequence. Pasting never starts it automatically." : model.automationStatus)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if model.automationRunning {
                        Button("Stop sequence", systemImage: "stop.fill") { model.send("stopscan") }.tint(.red)
                    } else {
                        Button("Start sequence", systemImage: "play.fill") {
                            do {
                                let plan = try TargetPlanConfiguration(target: target, actions: model.targetActions, secondsPerAction: model.actionDuration, authorizedActiveTests: model.authorizedTargetTests)
                                model.automation.start(plan)
                            } catch { model.error = error.localizedDescription }
                        }.buttonStyle(.borderedProminent)
                            .disabled(!model.canSend || !target.supportedByESP32S2 || model.targetActions.isEmpty || (model.targetActions.contains(where: \.transmits) && !model.authorizedTargetTests))
                    }
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.35)))
        }
    }
}
