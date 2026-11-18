import Foundation
import MarauderCore

struct WiFiJoinTests {
    private let bssid = "02:11:22:33:44:55"

    private func target(ssid: String = "Workshop", channel: Int = 6) throws -> AccessPoint {
        var inventory = NetworkInventory()
        inventory.consume(.accessPoint(bssid: bssid, ssid: ssid, channel: channel, rssi: -50))
        return try unwrap(inventory.accessPoints[bssid])
    }

    func verifiesDuplicateAPsAndWaitsForFirmwarePrompt() throws {
        var join = try WiFiJoin(target: target(), password: "example wifi key")
        expectNil(try join.receive("#stopscan"))
        expectCommand(try join.receive("Stopping WiFi tran/recv"), "list -a")
        expectNil(try join.receive("0 selected"))
        expectNil(try join.receive("> #list -a"))
        expectNil(try join.receive("[0][CH:6] Workshop -33"))
        expectNil(try join.receive("[1][CH:6] Workshop -50"))
        expectCommand(try join.receive("0 selected"), "info -a 0")
        expectNil(try join.receive("ESSID: Workshop"))
        expectNil(try join.receive("BSSID: 02:00:00:00:00:01"))
        expectNil(try join.receive("Channel: 6"))
        expectCommand(try join.receive("Security: WPA2"), "info -a 1")
        expectNil(try join.receive("ESSID: Workshop"))
        expectNil(try join.receive("BSSID: \(bssid.lowercased())"))
        expectNil(try join.receive("Channel: 6"))
        guard case .sendCredentials(let credentials) = try join.receive("Security: WPA2") else {
            fail("Expected a join command only after verifying the BSSID"); return
        }
        expectEqual(credentials.wireValue, #"join -a 1 -p "example wifi key""#)
        expectNil(try join.receive(">"))
        expectNil(try join.receive("Using SSID: Workshop"))

        var framer = LineFramer()
        expectEqual(framer.append(Data("Connecting to WiFi...>".utf8)), [])
        expectNil(framer.takeWiFiJoinPrompt())
        expectEqual(framer.append(Data(" ".utf8)), [])
        let prompt = try unwrap(framer.takeWiFiJoinPrompt())
        guard case .joined = try join.receive(prompt) else { fail("Expected confirmed Wi-Fi join"); return }
        expectNil(framer.takeWiFiJoinPrompt())
        expectEqual(framer.append(Data("#help\r\n".utf8)), ["#help"])
    }

    func rejectsUnsupportedAndUnverifiedTargets() throws {
        expectThrows(try WiFiJoin(target: target(channel: 36), password: "example wifi key"))
        expectThrows(try WiFiJoin(target: target(ssid: ""), password: "example wifi key"))
        var join = try WiFiJoin(target: target(), password: "example wifi key")
        _ = try join.receive("Stopping WiFi tran/recv")
        _ = try join.receive("#list -a")
        _ = try join.receive("[0][CH:6] Workshop -50")
        _ = try join.receive("[1][CH:36] Workshop -45")
        expectThrows(try join.receive("0 selected"))

        join = try WiFiJoin(target: target(), password: "example wifi key")
        _ = try join.receive("Stopping WiFi tran/recv")
        _ = try join.receive("#list -a")
        _ = try join.receive("[0][CH:6] Workshop -50")
        _ = try join.receive("0 selected")
        _ = try join.receive("ESSID: Workshop")
        _ = try join.receive("BSSID: \(bssid)")
        _ = try join.receive("Channel: 11")
        expectThrows(try join.receive("Security: WPA2"))
    }

    func handlesRejectedPasswordAndKeepsCommandEchoRecognizable() throws {
        var join = try WiFiJoin(target: target(), password: "example wifi key")
        for line in ["Stopping WiFi tran/recv", "#list -a", "[0][CH:6] Workshop -50", "0 selected",
                     "ESSID: Workshop", "BSSID: \(bssid)", "Channel: 6", "Security: WPA2", "Using SSID: Workshop"] {
            _ = try join.receive(line)
        }
        expectThrows(try join.receive("Could not connect to WiFi network"))
        expectFalse(WiFiJoin.isCompletionPrompt("Connecting to WiFi... Failed > "))
        expectTrue(WiFiJoinCommand.isJoinCommand(#"> #join -a 0 -p "example wifi key""#))
        expectTrue(WiFiJoinCommand.isJoinCommand("join -s"))
        expectFalse(WiFiJoinCommand.isJoinCommand("Using SSID: join -s"))
    }

    func encodesPasswordsForFirmwareTokenizer() throws {
        let password = #"  example"' {wifi}\key  "#
        let command = try WiFiJoinCommand(index: 2, password: password)
        expectEqual(tokens(command.wireValue), ["join", "-a", "2", "-p", password])
        expectEqual(tokens(try WiFiJoinCommand(index: 2, password: "").wireValue), ["join", "-p", "", "-a", "2"])
        expectThrows(try WiFiJoinCommand(index: 2, password: "short"))
        expectThrows(try WiFiJoinCommand(index: 2, password: "extra\ncommand"))
        expectThrows(try WiFiJoinCommand(index: 2, password: String(repeating: "x", count: 64)))
        _ = try WiFiJoinCommand(index: 2, password: String(repeating: "a1", count: 32))
    }

    private func expectCommand(_ update: WiFiJoin.Update?, _ expected: String) {
        if case .send(let command) = update { expectEqual(command, expected) }
        else { fail("Expected firmware command \(expected)") }
    }

    private func tokens(_ command: String) -> [String] {
        var result: [String] = []
        var token = ""
        var quote: Character?
        for character in command {
            if character == quote {
                quote = nil
            } else if quote == nil && (character == "\"" || character == "'") {
                quote = character
            } else if quote == nil && character == " " {
                result.append(token)
                token = ""
            } else {
                token.append(character)
            }
        }
        if !token.isEmpty { result.append(token) }
        return result
    }
}
