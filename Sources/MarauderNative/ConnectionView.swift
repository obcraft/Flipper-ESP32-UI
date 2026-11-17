import SwiftUI
import MarauderCore

struct ConnectionView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "Device connection", subtitle: "Connect through your Flipper Zero’s USB-UART bridge.")
                HStack(spacing: 18) {
                    device("Mac", "desktopcomputer")
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    device("USB-C · Flipper Zero", "cable.connector")
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    device("UART · ESP32 Marauder", "cpu")
                }.frame(maxWidth: .infinity).padding(20).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Picker("Serial port", selection: $model.selectedPort) {
                                if model.devices.isEmpty { Text("No USB serial ports found").tag("") }
                                ForEach(model.devices) { device in Text(device.name).tag(device.path) }
                            }.disabled(model.connected).frame(maxWidth: 500)
                            Button { model.refreshPorts() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh USB serial ports")
                            Spacer()
                        }
                        HStack(spacing: 24) {
                            Picker("Baud", selection: $model.baud) { ForEach(SerialPort.baudRates, id: \.self) { Text(String($0)).tag($0) } }.frame(width: 190).disabled(model.connected)
                            Picker("Line ending", selection: $model.lineEnding) {
                                Text("LF").tag("\n"); Text("CRLF").tag("\r\n"); Text("CR").tag("\r")
                            }.frame(width: 160).disabled(model.connected)
                            Text("8 data bits · no parity · 1 stop bit").font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        HStack {
                            Circle().fill(model.connected ? Color.green : Color.secondary).frame(width: 8, height: 8)
                            Text(model.status).font(.callout)
                            Spacer()
                            if model.connected { Button("Disconnect") { model.disconnect() } }
                            else { Button("Connect to Flipper") { model.connect() }.buttonStyle(.borderedProminent).disabled(model.selectedPort.isEmpty) }
                        }
                    }.padding(12)
                } label: { Label("Serial connection", systemImage: "cable.connector") }
                HStack(alignment: .top, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            step(1, "Attach your Wi-Fi board", "The ESP32 board should already be flashed with the Flipper build of Marauder.")
                            step(2, "Connect USB-C to the Flipper", "Use the Flipper’s USB-C port for this connection.")
                            step(3, "Open GPIO → USB-UART Bridge", "On the Flipper, select USB channel 0 and set baud to 115200. Leave the bridge running.")
                            step(4, "Connect here", "Use Check connection to request the firmware command list. Close qFlipper and other serial terminals if the port is busy.")
                        }.padding(12)
                    } label: { Label("On your Flipper", systemImage: "list.number") }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Command profile", selection: $model.modernFirmware) {
                                Text("Current firmware").tag(true)
                                Text("Classic firmware").tag(false)
                            }.pickerStyle(.menu)
                            Text(model.modernFirmware ? "Uses sniffbeacon for access points and scanall for access points + stations." : "Uses scanap and scansta, matching the original web interface.").font(.callout).foregroundStyle(.secondary)
                            Text("Read the device’s Help output to check which commands your installed build supports. Unknown output remains visible in the terminal.").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Info") { model.send("info") }
                                Button("Check connection") { model.send("help") }
                            }.disabled(!model.canSend)
                            Link("Marauder connection guide ↗", destination: URL(string: "https://github.com/justcallmekoko/ESP32Marauder/wiki/CLI")!).font(.caption)
                        }.padding(12)
                    } label: { Label("Firmware compatibility", systemImage: "cpu") }
                }
                Text("Your session stays on this Mac. Network data is held in memory; exports are saved only when you choose. Command history is saved locally and can be cleared from Session.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
    private func device(_ name: String, _ symbol: String) -> some View {
        VStack(spacing: 9) { Image(systemName: symbol).font(.title2).foregroundStyle(.orange); Text(name).font(.caption.weight(.medium)) }.frame(maxWidth: .infinity)
    }
    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(.orange).frame(width: 22, height: 22).background(Color.orange.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.callout.weight(.medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
