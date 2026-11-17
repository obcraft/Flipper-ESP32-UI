import SwiftUI
import MarauderCore

struct NetworksView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingWatchlist = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SectionHeader(title: "Nearby networks", subtitle: model.demo ? "A simulated workspace to explore before connecting." : "Discover access points and inspect their associated stations.")
                Spacer()
                Button("Watchlist (\(model.watchedBSSIDs.count))", systemImage: "eye") { showingWatchlist = true }
                Button("Scan", systemImage: "wifi") { model.send(model.scanAP) }.buttonStyle(.borderedProminent).disabled(!model.canSend)
            }
            HStack(spacing: 12) {
                Metric(label: "Access points", value: "\(model.networks.filter { $0.bssid != nil }.count)", symbol: "wifi")
                Metric(label: "Stations", value: "\(model.stationCount)", symbol: "laptopcomputer")
                Metric(label: "Channels observed", value: "\(Set(model.networks.map(\.channel)).count)", symbol: "waveform")
            }
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a network, BSSID, or station", text: $model.search).textFieldStyle(.plain)
                    if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(8).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                Picker("Sort", selection: $model.sort) {
                    ForEach(["Signal", "Name", "Channel", "Stations"], id: \.self) { Text($0) }
                }.frame(width: 150)
                Toggle("Details", isOn: $model.detailed).toggleStyle(.button).controlSize(.small)
                Menu {
                    Button("Refresh firmware list") { model.send("list -a") }.disabled(!model.canSend)
                    Button("Toggle selected APs on device") { model.selectOnDevice() }.disabled(!model.canSend || model.selectedNetworks.isEmpty)
                    Button("Use selection in workflow") { model.useSelectedIndices(); model.workflowDetailVisible = true; model.destination = .workflows }.disabled(model.selectedNetworks.isEmpty)
                    Divider()
                    Button("Export networks…") { model.exportNetworks() }
                    Button("Clear local network view") { model.clearNetworks() }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
            }
            HStack(spacing: 0) {
                networkTable.frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.detailed && model.selectedAP != nil {
                    Divider().padding(.horizontal, 8)
                    inspector.frame(width: 220)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text("\(model.filteredNetworks.count) entries")
                Spacer()
                Text(model.selectedNetworks.isEmpty ? "Select a network to inspect it" : "\(model.selectedNetworks.count) selected")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(20).background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingWatchlist) { watchlist }
    }
    private var watchlist: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Watchlist", subtitle: "Channel and signal update when a scan observes one of your checked access points.")
            if model.watchedNetworks.isEmpty {
                ContentUnavailableView("No watched networks in the scan results", systemImage: "eye",
                    description: Text("Scan nearby networks and check the ones you want to follow in the Watch column."))
            } else {
                Table(model.watchedNetworks) {
                    TableColumn("Network", value: \.displayName)
                    TableColumn("BSSID") { ap in Text(ap.id).font(.system(.caption, design: .monospaced)) }.width(130)
                    TableColumn("CH") { ap in Text(String(ap.channel)) }.width(36)
                    TableColumn("Signal") { ap in SignalView(rssi: ap.rssi) }.width(78)
                    TableColumn("Last seen") { ap in
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(ap.lastSeen.map { relativeAge($0, now: context.date) } ?? "—")
                        }
                    }.width(82)
                }
            }
            HStack {
                Button("Clear watchlist") { model.watchedBSSIDs.removeAll() }.disabled(model.watchedBSSIDs.isEmpty)
                Spacer()
                Button("Done") { showingWatchlist = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 650, height: 360)
    }
    @ViewBuilder private var networkTable: some View {
        if model.filteredNetworks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: model.search.isEmpty ? "wifi" : "magnifyingglass")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                Text(model.search.isEmpty ? "No networks yet" : "No matching networks").font(.headline)
                Text(model.search.isEmpty ? (model.canSend ? "Start a scan to discover nearby access points." : "Connect your Flipper or explore the demo.") : "Try a different name or MAC address.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if !model.canSend && model.search.isEmpty {
                    Button("Explore demo") { model.startDemo() }.buttonStyle(.bordered).padding(.top, 4)
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        } else { populatedTable }
    }
    private var populatedTable: some View {
        Table(model.filteredNetworks, selection: $model.selectedNetworks) {
            TableColumn("Watch") { ap in
                if let bssid = ap.bssid {
                    Toggle("Watch \(ap.displayName), \(bssid)", isOn: Binding(
                        get: { model.watchedBSSIDs.contains(bssid) },
                        set: { watch in
                            if watch { model.watchedBSSIDs.insert(bssid) }
                            else { model.watchedBSSIDs.remove(bssid) }
                        }
                    )).toggleStyle(.checkbox).labelsHidden()
                }
            }.width(45)
            TableColumn("Network") { ap in
                HStack(spacing: 8) {
                    Image(systemName: ap.isHidden ? "eye.slash" : "wifi").foregroundStyle(ap.isHidden ? .secondary : .primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ap.displayName).fontWeight(.medium).lineLimit(1)
                        if model.detailed { Text(ap.bssid ?? "List entry · BSSID unresolved").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
                    }
                    if ap.selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Selected on the device") }
                }.padding(.vertical, 4)
            }.width(min: 160, ideal: 225)
            TableColumn("CH") { ap in Text("\(ap.channel)").monospacedDigit().foregroundStyle(.secondary) }.width(34)
            TableColumn("Signal") { ap in SignalView(rssi: ap.rssi) }.width(90)
            TableColumn("STA") { ap in Text("\(ap.stations.count)").monospacedDigit() }.width(34)
            TableColumn("Index") { ap in Text(ap.index.map(String.init) ?? "—").monospacedDigit().foregroundStyle(.secondary) }.width(40)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("NETWORK DETAILS").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
                if let ap = model.selectedAP {
                    Image(systemName: "wifi").font(.system(size: 32)).foregroundStyle(.orange)
                    Text(ap.displayName).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text(ap.bssid ?? "BSSID unavailable").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    Divider()
                    detail("Channel", "\(ap.channel)")
                    detail("Signal", ap.rssi.map { "\($0) dBm" } ?? "Unknown")
                    detail("Firmware index", ap.index.map(String.init) ?? "Request List APs")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        detail("Observed", ap.lastSeen.map { relativeAge($0, now: context.date) } ?? "List entry only")
                    }
                    if ap.bssid == nil { Text("The firmware list omits MAC addresses. Duplicate names are kept separate until their identity is known.").font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    Text("STATIONS · \(ap.stations.count)").font(.system(size: 10, weight: .bold)).tracking(1)
                    if ap.stations.isEmpty { Text("No stations observed yet.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(ap.stations) { station in
                        Label(station.mac, systemImage: "laptopcomputer").font(.system(size: 10, design: .monospaced))
                    }
                    Button("Use in workflow", systemImage: "arrow.up.forward.square") {
                        model.useSelectedIndices(); model.workflowDetailVisible = true; model.destination = .workflows
                    }.disabled(ap.index == nil)
                } else {
                    Image(systemName: "cursorarrow.click").font(.system(size: 30)).foregroundStyle(.tertiary).padding(.top, 22)
                    Text("Select a network").font(.headline)
                    Text("Inspect its signal, device index, and connected stations. Command-click to select multiple networks.").font(.callout).foregroundStyle(.secondary)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.caption)
    }
}

struct SignalView: View {
    let rssi: Int?
    private var level: Int { guard let rssi else { return 0 }; return rssi > -55 ? 4 : rssi > -70 ? 3 : rssi > -85 ? 2 : 1 }
    private var color: Color { level >= 3 ? .green : level == 2 ? .orange : .red }
    var body: some View {
        HStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4) { i in RoundedRectangle(cornerRadius: 1).fill(i < level ? color : Color.secondary.opacity(0.18)).frame(width: 3, height: CGFloat(4 + i * 3)) }
            }.frame(height: 16)
            Text(rssi.map(String.init) ?? "—").font(.system(size: 11, design: .monospaced))
        }.accessibilityLabel(rssi.map { "Signal \($0) dBm" } ?? "Signal unknown")
    }
}

func relativeAge(_ date: Date, now: Date = Date()) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    return seconds < 60 ? "\(seconds)s ago" : seconds < 3600 ? "\(seconds / 60)m ago" : "\(seconds / 3600)h ago"
}

struct StationsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                SectionHeader(title: "Connected stations", subtitle: "Stations grouped by their observed access point.")
                Spacer()
                Button("Discover", systemImage: "antenna.radiowaves.left.and.right") { model.send(model.scanStations) }.disabled(!model.canSend)
                Button("List indices") { model.send("list -c") }.disabled(!model.canSend)
            }
            if model.stationCount == 0 {
                ContentUnavailableView("No stations observed", systemImage: "laptopcomputer", description: Text("Discover networks, then stations. Firmware station indices are available in the terminal with List indices."))
            } else {
                List {
                    ForEach(model.networks.filter { !$0.stations.isEmpty }) { ap in
                        Section {
                            ForEach(ap.stations) { station in
                                HStack {
                                    Image(systemName: "laptopcomputer").foregroundStyle(.orange)
                                    Text(station.mac).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                    Spacer()
                                    TimelineView(.periodic(from: .now, by: 1)) { context in Text(relativeAge(station.lastSeen, now: context.date)).foregroundStyle(.secondary).font(.caption) }
                                }.padding(.vertical, 6)
                            }
                        } header: { Text("\(ap.displayName) · \(ap.bssid ?? "Unknown")") }
                    }
                }.listStyle(.inset)
            }
        }.padding(22)
    }
}
