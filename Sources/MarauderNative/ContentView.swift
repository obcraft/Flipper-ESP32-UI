import SwiftUI
import MarauderCore
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("terminalPanelHeight") private var terminalPanelHeight = 210.0
    @State private var dragStart: Double?
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.error { errorBanner(error) }
                GeometryReader { geometry in
                    let limit = max(150.0, min(360.0, geometry.size.height - 360))
                    let height = min(max(150, terminalPanelHeight), limit)
                    VStack(spacing: 0) {
                        Group {
                            switch model.destination ?? .networks {
                            case .networks: NetworksView()
                            case .stations: StationsView()
                            case .workflows: WorkflowsView()
                            case .connection: ConnectionView()
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped().layoutPriority(1)
                        Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.5))
                            .frame(height: 5)
                            .overlay(Capsule().fill(.secondary.opacity(0.4)).frame(width: 36, height: 2))
                            .contentShape(Rectangle())
                            .onHover { hovering in (hovering ? NSCursor.resizeUpDown : NSCursor.arrow).set() }
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                if dragStart == nil { dragStart = height }
                                terminalPanelHeight = min(limit, max(150, (dragStart ?? height) - value.translation.height))
                            }.onEnded { _ in dragStart = nil })
                            .accessibilityLabel("Resize terminal")
                        TerminalView().frame(height: height).clipped()
                    }
                }
                statusBar
            }
            .navigationTitle(model.destination?.rawValue ?? "Networks")
            .toolbar { toolbar }
        }
        .frame(minWidth: 1040, minHeight: 710)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.orange.gradient).frame(width: 42, height: 42)
                    Image(systemName: "waveform.path").font(.system(size: 23, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("MARAUDER").font(.system(size: 14, weight: .heavy, design: .rounded)).tracking(1)
                    Text("Flipper companion").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(18).padding(.top, 4)
            List(selection: $model.destination) {
                Section("Workspace") {
                    ForEach(Destination.allCases) { destination in
                        Label(destination.rawValue, systemImage: destination.symbol).tag(destination)
                    }
                }

            }.listStyle(.sidebar)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle().fill(model.demo ? .purple : model.connected ? .green : .secondary).frame(width: 7, height: 7)
                    Text(model.demo ? "DEMO SESSION" : model.connected ? "USB CONNECTED" : "DEVICE OFFLINE")
                        .font(.system(size: 10, weight: .bold)).tracking(1)
                }
                Text(model.demo ? "Simulated networks. No radio activity." : "Mac → Flipper Zero → ESP32")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.connected {
                    Button(model.demo ? "Exit demo" : "Explore demo", systemImage: model.demo ? "xmark.circle" : "play.circle") {
                        if model.demo { model.endDemo() } else { model.startDemo() }
                    }.buttonStyle(.bordered).controlSize(.small)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35))
        }
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 10) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(width: 14, height: 16)
                Text("USB-UART")
                    .font(.system(size: 12, weight: .semibold))
                Rectangle().fill(.secondary.opacity(0.35))
                    .frame(width: 1, height: 12)
                Text("\(model.baud.formatted(.number.grouping(.never))) baud")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .help("USB-UART bridge · \(model.baud) baud · 8N1")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.send("stopscan") } label: { HStack(spacing: 5) { Image(systemName: "stop.fill"); Text("Stop") } }
                .tint(.red).disabled(!model.canSend).help("Stop the active device operation (⌘.)")
            Divider()
            if model.connected {
                Button { model.disconnect() } label: { HStack(spacing: 5) { Image(systemName: "cable.connector.slash"); Text("Disconnect") } }
            } else {
                Button { model.connect() } label: { HStack(spacing: 5) { Image(systemName: "cable.connector"); Text("Connect") } }
                    .disabled(model.selectedPort.isEmpty).help(model.selectedPort.isEmpty ? "Connect a USB device first" : model.selectedPort)
            }
        }
    }
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message).font(.callout).textSelection(.enabled)
            Spacer()
            Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
        }.padding(12).background(Color.orange.opacity(0.10))
    }
    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(model.status).lineLimit(1)
            Spacer()
            if let operation = model.operation {
                Text(operation).foregroundStyle(.orange).lineLimit(1)
                Button("Mark stopped") { model.acknowledgeStopped() }.buttonStyle(.link)
                    .help("Use only after verifying in the terminal that the operation has stopped")
            }
            Text("RX \(model.receivedBytes.formatted()) B  ·  TX \(model.transmittedBytes.formatted()) B")
                .monospacedDigit()
        }.font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 7).background(.bar)
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 21, weight: .semibold, design: .rounded))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

struct Metric: View {
    let label: String
    let value: String
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.orange)
                .frame(width: 30, height: 30).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }
}
