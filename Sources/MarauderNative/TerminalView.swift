import SwiftUI

struct TerminalView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var commandFocused: Bool
    private var visibleLines: [TerminalLine] {
        model.terminal.filter { model.terminalSearch.isEmpty || $0.text.localizedCaseInsensitiveContains(model.terminalSearch) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "terminal").foregroundStyle(.orange)
                Text("TERMINAL").font(.system(size: 10, weight: .bold)).tracking(1.2)
                Text("\(model.terminal.count) lines").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField("Filter output", text: $model.terminalSearch).textFieldStyle(.roundedBorder).frame(width: 160)
                Toggle("Follow", isOn: $model.followTerminal).toggleStyle(.checkbox).controlSize(.small)
                Button { model.exportTerminal() } label: { Image(systemName: "square.and.arrow.up") }.help("Export terminal…").accessibilityLabel("Export terminal")
                Button { model.clearTerminal() } label: { Image(systemName: "trash") }.help("Clear terminal (⌘L)").accessibilityLabel("Clear terminal")
            }.buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 9).background(.bar)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if model.terminal.isEmpty {
                            Text("Serial output will appear here.").foregroundStyle(Color.gray).padding(.vertical, 10)
                        }
                        ForEach(visibleLines) { line in
                            HStack(alignment: .top, spacing: 12) {
                                Text(line.date, format: .dateTime.hour().minute().second()).foregroundStyle(Color.white.opacity(0.30)).frame(width: 65, alignment: .leading)
                                Text(line.kind == .command ? "> \(line.text)" : line.text).foregroundStyle(color(line.kind)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            }.id(line.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.font(.system(size: 11, design: .monospaced)).padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                }.background(Color(red: 0.065, green: 0.075, blue: 0.09))
                .onChange(of: model.terminal.last?.id) { _, _ in if model.followTerminal { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: model.followTerminal) { _, follow in if follow { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            HStack(spacing: 10) {
                Text(">").font(.system(.body, design: .monospaced).weight(.bold)).foregroundStyle(.orange)
                TextField(model.canSend ? "Enter a Marauder command…" : "Connect or open demo to send commands", text: $model.command)
                    .font(.system(size: 12, design: .monospaced)).textFieldStyle(.plain)
                    .focused($commandFocused).onSubmit { model.sendInput() }
                    .onKeyPress(.upArrow) { model.historyPrevious(); return .handled }
                    .onKeyPress(.downArrow) { model.historyNext(); return .handled }
                Menu {
                    if model.history.isEmpty { Text("No command history") }
                    ForEach(model.history, id: \.self) { command in Button(command) { model.command = command; commandFocused = true } }
                    Divider()
                    Button("Clear history") { model.clearHistory() }
                } label: { Image(systemName: "clock.arrow.circlepath") }.menuStyle(.borderlessButton).frame(width: 24).help("Command history · ↑ / ↓")
                Button("Send", systemImage: "arrow.up") { model.sendInput() }.buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!model.canSend || model.wifiJoinInProgress || model.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
        }
    }
    private func color(_ kind: TerminalLine.Kind) -> Color {
        switch kind { case .received: return Color(red: 0.68, green: 0.84, blue: 0.73); case .command: return .orange; case .info: return Color(red: 0.57, green: 0.71, blue: 0.90); case .error: return .red }
    }
}
