import Foundation
import MarauderCore

final class ParserTests {
    func testClassicScanAndANSI() {
        let parsed = MarauderParser.parse("\u{1b}[32mRSSI: -54 Ch: 6 BSSID: aa:bb:cc:dd:ee:ff ESSID: Office WiFi\u{1b}[0m")
        expectEqual(parsed, .accessPoint(bssid: "AA:BB:CC:DD:EE:FF", ssid: "Office WiFi", channel: 6, rssi: -54))
    }
    func testModernScanAndHiddenNetwork() {
        expectEqual(MarauderParser.parse("-71 Ch: 11 00:11:22:33:44:55 ESSID:"), .accessPoint(bssid: "00:11:22:33:44:55", ssid: "", channel: 11, rssi: -71))
    }
    func testModernListSeparatesSignalFromName() {
        guard case .listing(let row) = MarauderParser.parse("[2][CH:6] Office WiFi -63 (selected)") else { return fail("Expected listing") }
        expectEqual(row.ssid, "Office WiFi"); expectEqual(row.rssi, -63); expectTrue(row.selected)
    }
    func testClassicListPreservesNameAndIndex() {
        guard case .listing(let row) = MarauderParser.parse("[7][CH:11] Building 42 (selected)") else { return fail("Expected listing") }
        expectEqual(row.ssid, "Building 42"); expectNil(row.rssi); expectEqual(row.index, 7)
    }
    func testInvalidOutputDoesNotInventNetworks() {
        expectNil(MarauderParser.parse("RSSI: -55 Ch: 6 BSSID: not-a-mac ESSID: Fake"))
        expectNil(MarauderParser.parse("unrecognized firmware log"))
        expectNil(MarauderParser.parse("RSSI: -999 Ch: 6 BSSID: AA:BB:CC:DD:EE:FF ESSID: Fake"))
    }
    func testStationDirectionsNormalizeMACs() {
        let expected = ParsedEvent.station(ap: "AA:AA:AA:AA:AA:AA", mac: "BB:BB:BB:BB:BB:BB")
        expectEqual(MarauderParser.parse("4: ap: aa:aa:aa:aa:aa:aa -> sta: bb:bb:bb:bb:bb:bb"), expected)
        expectEqual(MarauderParser.parse("4: sta: bb:bb:bb:bb:bb:bb -> ap: aa:aa:aa:aa:aa:aa"), expected)
    }
    func testFramingPreservesSplitUnicodeAndCRLF() {
        var framer = LineFramer()
        let bytes = Array("Cafe ☕\r\nsecond\n".utf8)
        var lines: [String] = []
        for byte in bytes { lines += framer.append(Data([byte])) }
        expectEqual(lines, ["Cafe ☕", "second"])
    }
    func testOversizedLineDropsAndRecovers() {
        var framer = LineFramer(maximumLineBytes: 4)
        expectEqual(framer.append(Data("toolong\nok\n".utf8)), ["ok"])
        expectEqual(framer.droppedLines, 1)
        expectEqual(framer.append(Data("fine\n".utf8)), ["fine"])
    }
    func testFramerResetDoesNotLeakBetweenSessions() {
        var framer = LineFramer()
        expectTrue(framer.append(Data("old partial".utf8)).isEmpty)
        framer.reset()
        expectEqual(framer.append(Data("new\n".utf8)), ["new"])
    }
}

final class InventoryTests {
    private let one = "AA:AA:AA:AA:AA:01"
    private let two = "AA:AA:AA:AA:AA:02"
    func testSameSSIDAndChannelRemainDistinct() {
        var inventory = NetworkInventory()
        inventory.consume(.accessPoint(bssid: one, ssid: "Shared", channel: 6, rssi: -40))
        inventory.consume(.accessPoint(bssid: two, ssid: "Shared", channel: 6, rssi: -70))
        expectEqual(inventory.accessPoints.count, 2)
        inventory.consume(.listing(APListing(index: 0, channel: 6, ssid: "Shared", rssi: -40, selected: true)))
        expectEqual(inventory.accessPoints.count, 3)
        expectNil(inventory.accessPoints[one]?.index)
        expectNil(inventory.accessPoints[two]?.index)
        expectEqual(inventory.accessPoints["index:0"]?.index, 0)
    }
    func testListDoesNotFalsifyLastSeen() {
        var inventory = NetworkInventory()
        let observed = Date(timeIntervalSince1970: 10)
        inventory.consume(.accessPoint(bssid: one, ssid: "Lab", channel: 1, rssi: -40), at: observed)
        inventory.consume(.listing(APListing(index: 3, channel: 1, ssid: "Lab", rssi: -45, selected: true)), at: observed.addingTimeInterval(60))
        expectEqual(inventory.accessPoints[one]?.lastSeen, observed)
        expectEqual(inventory.accessPoints[one]?.index, 3)
        inventory.invalidateIndices()
        expectNil(inventory.accessPoints[one]?.index)
        expectEqual(inventory.accessPoints[one]?.lastSeen, observed)
    }
    func testStationArrivesBeforeAccessPoint() {
        var inventory = NetworkInventory()
        inventory.consume(.station(ap: one, mac: two))
        inventory.consume(.accessPoint(bssid: one, ssid: "Lab", channel: 1, rssi: -40))
        expectEqual(inventory.accessPoints[one]?.stations.map(\.mac), [two])
        inventory.consume(.station(ap: one, mac: two))
        expectEqual(inventory.accessPoints[one]?.stations.count, 1)
        // Event sequence numbers are not firmware station indices.
        expectNil(inventory.accessPoints[one]?.stations.first?.index)
    }
    func testClearDoesNotReplayOldData() {
        var inventory = NetworkInventory()
        inventory.consume(.accessPoint(bssid: one, ssid: "Lab", channel: 1, rssi: -40))
        inventory.clear()
        expectTrue(inventory.accessPoints.isEmpty)
        expectNil(MarauderParser.parse("ordinary unrelated output"))
        expectTrue(inventory.accessPoints.isEmpty)
    }
}

final class WorkflowTests {
    func testManualPreviewUsesDifferentSourceAndDestination() throws {
        let workflow = try unwrap(Workflow.catalog.first { $0.id == "manual" })
        let value = try workflow.render(workflow.steps[0], values: ["source": "00:11:22:33:44:55", "destination": "AA:BB:CC:DD:EE:FF"], modern: true)
        expectEqual(value, "attack -t deauth -s 00:11:22:33:44:55 -d AA:BB:CC:DD:EE:FF")
    }
    func testInvalidInputsAndMultipleCommandsAreRejected() {
        expectThrows(try CommandValidation.validate("info\nreboot"))
        expectThrows(try CommandValidation.validate("info\rhelp"))
        expectThrows(try CommandValidation.validate("select -a {targets}"))
        expectFalse(CommandValidation.indices("0,,1"))
        expectFalse(CommandValidation.indices("-1"))
        expectFalse(CommandValidation.mac("00:11:22"))
    }
    func testSSIDWithSpacesIsPreserved() throws {
        let workflow = try unwrap(Workflow.catalog.first { $0.id == "custom" })
        expectEqual(try workflow.render(workflow.steps[0], values: ["name": "My Lab Network"], modern: true), "ssid -a -n \"My Lab Network\"")
        expectThrows(try workflow.render(workflow.steps[0], values: ["name": "bad\" name"], modern: true))
    }
    func testProfilesAndStopBeforeList() throws {
        let workflow = Workflow.catalog[0]
        expectEqual(try workflow.render(workflow.steps[0], values: [:], modern: true), "sniffbeacon")
        expectEqual(try workflow.render(workflow.steps[0], values: [:], modern: false), "scanap")
        expectEqual(workflow.steps[1].command, "stopscan")
        expectEqual(workflow.steps[2].command, "list -a")
        expectEqual(Set(Workflow.catalog.map(\.id)).count, Workflow.catalog.count)
    }
}
