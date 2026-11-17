import Foundation
import MarauderCore

// Explicit diagnostic only: never scans or changes firmware settings.
let args = CommandLine.arguments
if args.count < 2 {
    for device in SerialDevice.available() { print(device.path) }
    exit(0)
}
let port = SerialPort()
var framer = LineFramer()
do {
    try port.open(path: args[1])
    defer { port.close() }
    print("Opened \(args[1]) at 115200 8N1")
    for command in (args.contains("--info") ? ["help", "info"] : ["help"]) {
        try port.send(command)
        print("> \(command)")
        let until = Date().addingTimeInterval(3)
        while Date() < until {
            for line in framer.append(try port.readAvailable()) { print(MarauderParser.clean(line)) }
            Thread.sleep(forTimeInterval: 0.03)
        }
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
