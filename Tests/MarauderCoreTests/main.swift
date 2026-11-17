import Foundation
import MarauderCore
import Darwin

// A dependency-free test runner so checks also work with macOS Command Line Tools,
// where XCTest is not installed. Exits nonzero on any failure.
var failures = 0
var checks = 0
var skipped = 0
func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failures += 1; print("FAIL \(file):\(line): \(message)")
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { fail("Expected \(expected), got \(actual)", file: file, line: line) }
}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if !value { fail("Expected true", file: file, line: line) } }
func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if value { fail("Expected false", file: file, line: line) } }
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value != nil { fail("Expected nil", file: file, line: line) } }
func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); fail("Expected an error", file: file, line: line) } catch {}
}
func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw ValidationError("Unexpected nil") }; return value }
func run(_ name: String, _ body: () throws -> Void) {
    checks += 1; let before = failures
    do { try body() }
    catch let reason as CheckSkipped { skipped += 1; print("SKIP \(name): \(reason.reason)"); return }
    catch { fail("\(name): \(error)") }
    if before == failures { print("PASS \(name)") }
}
let parser = ParserTests()
run("classic output and ANSI", parser.testClassicScanAndANSI)
run("modern output and hidden networks", parser.testModernScanAndHiddenNetwork)
run("modern list signal fields", parser.testModernListSeparatesSignalFromName)
run("classic list names and indices", parser.testClassicListPreservesNameAndIndex)
run("unrecognized output is not fabricated", parser.testInvalidOutputDoesNotInventNetworks)
run("station direction and MAC normalization", parser.testStationDirectionsNormalizeMACs)
run("fragmented UTF-8 and CRLF", parser.testFramingPreservesSplitUnicodeAndCRLF)
run("oversized line recovery", parser.testOversizedLineDropsAndRecovers)
run("serial session framing isolation", parser.testFramerResetDoesNotLeakBetweenSessions)
let inventory = InventoryTests()
run("duplicate SSIDs remain distinct", inventory.testSameSSIDAndChannelRemainDistinct)
run("listing preserves observation timestamps", inventory.testListDoesNotFalsifyLastSeen)
run("out-of-order station observations", inventory.testStationArrivesBeforeAccessPoint)
run("cleared data does not return", inventory.testClearDoesNotReplayOldData)
let workflows = WorkflowTests()
run("manual source/destination command parity", workflows.testManualPreviewUsesDifferentSourceAndDestination)
run("input validation and command boundaries", workflows.testInvalidInputsAndMultipleCommandsAreRejected)
run("SSID spaces and quote validation", workflows.testSSIDWithSpacesIsPreserved)
run("firmware profiles and ordered survey", workflows.testProfilesAndStopBeforeList)
run("closed transport rejects writes") {
    let port = SerialPort()
    expectThrows(try port.send("info"))
    expectEqual(try port.readAvailable(), Data())
    expectFalse(port.isOpen)
}
run("transport rejects invalid baud before opening") {
    let port = SerialPort()
    expectThrows(try port.open(path: "/dev/nonexistent", baud: 12345))
    expectFalse(port.isOpen)
}
run("current firmware signal monitoring") {
    let workflow = try unwrap(Workflow.catalog.first { $0.id == "signal" })
    let step = try unwrap(workflow.steps.last)
    expectEqual(try workflow.render(step, values: ["targets": "3"], modern: true), "foxhunt -w 3")
    expectThrows(try workflow.render(step, values: ["targets": "1,2"], modern: true))
    expectEqual(try workflow.render(step, values: ["targets": "3"], modern: false), "sigmon")
}
run("hidden network list preserves empty SSID") {
    guard case .listing(let row) = MarauderParser.parse("[5][CH:11]  -64") else { fail("Expected a list row"); return }
    expectEqual(row.ssid, "")
    expectEqual(row.rssi, -64)
    var inventory = NetworkInventory()
    inventory.consume(.accessPoint(bssid: "AA:BB:CC:DD:EE:FF", ssid: "", channel: 11, rssi: -65))
    inventory.consume(.listing(row))
    expectEqual(inventory.accessPoints.count, 1)
    expectEqual(inventory.accessPoints["AA:BB:CC:DD:EE:FF"]?.index, 5)
}
run("real serial I/O through a pseudo-terminal", serialRoundTripCheck)
run("macOS network record import and 5 GHz rejection") {
    let record = "'Bellamyplein18' {length = 14, bytes = 0x42656c6c616d79706c65696e3138}, bssid=6a:07:1d:3d:05:a3, channel=[36, width=160], cc=DE, type=11ax, rssi=-45, rsn=(null), wpa=(null), wep=no"
    let target = try ImportedTarget.parse(record)
    expectEqual(target.name, "Bellamyplein18")
    let smartQuoted = record.replacingOccurrences(of: "'Bellamyplein18'", with: "‘Bellamyplein18’")
    expectEqual(try ImportedTarget.parse(smartQuoted).name, target.name)
    expectEqual(target.bssid, "6A:07:1D:3D:05:A3")
    expectEqual(target.channel, 36); expectEqual(target.width, 160)
    expectEqual(target.country, "DE"); expectEqual(target.rssi, -45)
    expectFalse(target.supportedByESP32S2)
    expectThrows(try TargetPlanConfiguration(target: target, actions: [.inspect], secondsPerAction: 15, authorizedActiveTests: false))
}
run("target resolution never falls back to a matching SSID") {
    let target = try ImportedTarget.parse("'Lab' {length=3}, bssid=02:11:22:33:44:55, channel=[6, width=20]")
    var inventory = NetworkInventory()
    inventory.consume(.accessPoint(bssid: "02:11:22:33:44:56", ssid: "Lab", channel: 6, rssi: -40))
    expectNil(target.resolve(in: Array(inventory.accessPoints.values)))
    inventory.consume(.accessPoint(bssid: target.bssid, ssid: "Lab", channel: 11, rssi: -40))
    expectNil(target.resolve(in: Array(inventory.accessPoints.values)))
    inventory.consume(.accessPoint(bssid: target.bssid, ssid: "Lab", channel: 6, rssi: -40))
    expectEqual(target.resolve(in: Array(inventory.accessPoints.values))?.bssid, target.bssid)
}
run("invalid and multiple target records are rejected") {
    expectThrows(try ImportedTarget.parse("not a network"))
    expectThrows(try ImportedTarget.parse("'Lab', bssid=FF:FF:FF:FF:FF:FF, channel=6"))
    expectThrows(try ImportedTarget.parse("'Lab', bssid=02:11:22:33:44:55, channel=0"))
    expectThrows(try ImportedTarget.parse("'Lab', bssid=02:11:22:33:44:55, channel=6, bssid=02:11:22:33:44:56"))
}
run("automatic plans are bounded and require active-test authorization") {
    let target = try ImportedTarget.parse("'Lab', bssid=02:11:22:33:44:55, channel=6")
    expectThrows(try TargetPlanConfiguration(target: target, actions: [.deauthTest], secondsPerAction: 15, authorizedActiveTests: false))
    expectThrows(try TargetPlanConfiguration(target: target, actions: [.signal], secondsPerAction: 121, authorizedActiveTests: false))
    expectThrows(try TargetPlanConfiguration(target: target, actions: [], secondsPerAction: 15, authorizedActiveTests: false))
    expectThrows(try TargetPlanConfiguration(target: target, actions: [.signal, .signal], secondsPerAction: 15, authorizedActiveTests: false))
    let plan = try TargetPlanConfiguration(target: target, actions: [.inspect, .signal], secondsPerAction: 5, authorizedActiveTests: false)
    expectEqual(plan.actions, [.inspect, .signal])
}
run("target actions retain channel and AP scope") {
    expectEqual(try TargetAction.pmkidCapture.command(index: 4, channel: 6, modern: true), "sniffpmkid -c 6 -l")
    expectEqual(try TargetAction.signal.command(index: 4, channel: 6, modern: true), "foxhunt -w 4")
    expectThrows(try TargetAction.deauthTest.command(index: 4, channel: 36, modern: true))
    expectThrows(try TargetAction.signal.command(index: -1, channel: 6, modern: true))
}
run("every former quick command has a guided workflow") {
    let required = ["survey", "station-survey", "ap-list", "station-list", "deauth-sniff", "pmkid-listen", "wardrive"]
    for id in required {
        let workflow = try unwrap(Workflow.catalog.first { $0.id == id })
        expectFalse(workflow.guide.start.isEmpty)
        expectFalse(workflow.guide.expected.isEmpty)
        expectFalse(workflow.guide.next.isEmpty)
    }
    let wardrive = try unwrap(Workflow.catalog.first { $0.id == "wardrive" })
    expectEqual(try wardrive.render(wardrive.steps[0], values: [:], modern: true), "wardrive")
    expectEqual(try wardrive.render(wardrive.steps[0], values: [:], modern: false), "wardrive -s")
}
print("\n\(checks - skipped) checks run, \(skipped) skipped, \(failures) failures")
exit(failures == 0 ? 0 : 1)
