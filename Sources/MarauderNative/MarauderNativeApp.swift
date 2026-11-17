import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MarauderNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Marauder", id: "main") {
            ContentView().environmentObject(model)
                .tint(.orange)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.shutdown() }
                .onAppear { if CommandLine.arguments.contains("--demo") && !model.demo { model.startDemo() } }
        }
        .defaultSize(width: 1320, height: 860)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Device") {
                Button("Connect") { model.connect() }.disabled(model.connected || model.selectedPort.isEmpty)
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Disconnect") { model.disconnect() }.disabled(!model.connected)
                Divider()
                Button("Stop operation") { model.send("stopscan") }.disabled(!model.canSend)
                    .keyboardShortcut(".", modifiers: [.command])
                Button("Firmware information") { model.send("info") }.disabled(!model.canSend)
                Button("Firmware help") { model.send("help") }.disabled(!model.canSend)
            }
            CommandMenu("Session") {
                Button("Export terminal…") { model.exportTerminal() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Export networks…") { model.exportNetworks() }
                Divider()
                Button("Clear terminal") { model.clearTerminal() }.keyboardShortcut("l", modifiers: [.command])
                Button("Clear command history") { model.clearHistory() }
            }
        }
    }
}
