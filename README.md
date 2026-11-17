# Marauder for macOS

A native SwiftUI companion for an ESP32 Wi-Fi board running Marauder, connected through a Flipper Zero USB-UART bridge. Built for macOS 14 or later. The bundled build is for Apple silicon.

## Open the app

Open **`dist/Marauder.app`** in Finder. It runs directly from this folder; you can also copy it to Applications. The local build is ad-hoc signed, not a notarized public release.

1. Attach the Marauder-flashed Wi-Fi board to your Flipper Zero.
2. Connect the Mac's USB-C cable to the **Flipper**, then open **GPIO → USB-UART Bridge** on the Flipper.
3. Set **USB channel 0**, **115200 baud**, and leave the bridge running.
4. In the Mac app, open **Connection**, select the Flipper serial port, and click **Connect**.
5. Click **Check connection** to request `help`. The terminal should show commands supported by your firmware.
6. Open **Networks** and start a scan. Stop it before switching operations; **List access points** retrieves the firmware indices used by workflows.

Connecting only opens the serial port. It does not start scans, transmit wireless packets, or automatically send `info`. Baud, framing (8N1), and LF line endings match the documented bridge defaults. qFlipper or another serial monitor can keep the port busy.

## Features

- Native SwiftUI window, sidebar, tables, menus, system light/dark appearance, keyboard shortcuts, and export dialogs.
- A network-first layout with a bounded, draggable terminal and a details inspector shown only for a selected network.
- USB serial discovery, exclusive port access, nonblocking buffered I/O, unplug handling, and byte counters.
- Current (`sniffbeacon` / `scanall`) and classic (`scanap` / `scansta`) command profiles.
- AP and station discovery, search, sorting, signal strength, selection state, and honest observation timestamps.
- Separate identities for distinct BSSIDs sharing a name/channel. The firmware's name-only list entries stay unresolved if a MAC cannot be matched unambiguously.
- Station MAC addresses and last-observed times. Authoritative station indices are read from `list -c` in the terminal; scan event numbers are not treated as indices.
- Custom commands, 50 locally persisted history entries, ↑/↓ recall, output filtering, terminal clearing, and plain-text log export.
- Network snapshot export as JSON. All network data remains in memory until explicitly exported.
- Sixteen guided workflows in a searchable card gallery. The former sidebar quick commands are now guides with prerequisites, expected output and next steps. Parameters are validated, exact commands are previewed, and each step is explicitly sent after reviewing the previous response.
- A completely isolated demo with synthetic networks and station relationships. No serial port is opened in demo mode.

**Shortcuts:** ⌘. stops an operation; ⇧⌘K connects; ⌘L clears terminal output; ⇧⌘S exports the terminal. Use the Session menu to clear command history.

Workflow support depends on the installed firmware. Current-profile signal monitoring uses `foxhunt -w` with one AP index. Classic-profile monitoring uses `sigmon`. The global Stop sends `stopscan`. “Mark stopped” is a manual fallback only after checking the terminal when a firmware build uses an unrecognized acknowledgement. Sent workflow steps indicate transmission, not firmware success.

## Paste a network and prepare an automatic sequence

Open **Workflows → Paste a network**, then paste a single macOS Wi-Fi record containing a quoted name, `bssid=…` and `channel=[…]`. The preview extracts the MAC address, channel, width, RSSI, country and Wi-Fi type. Importing sends nothing to the device.

The currently supported ESP32-S2 board is 2.4 GHz only. A record on channel 36 (5 GHz) can be imported for inspection, but execution is disabled. Use the exact 2.4 GHz BSSID; the app never substitutes another AP merely because its name matches.

Choose and reorder actions, set 5–120 seconds per timed action, then explicitly click **Start sequence**. Available actions are reading the selection, signal monitoring, channel-wide deauth observation, selected-AP PMKID capture, deauthentication testing and clone beacons. Active tests require explicit permission confirmation in the app. A deauth observation captures the channel, not only one BSSID; the action description makes this scope visible.

Each sequence stops existing work, discovers for 10 seconds, waits for a stop acknowledgement, reads a fresh AP list, requires a recently observed BSSID/channel with an unambiguous index, adjusts selection, and re-reads the list to verify exclusive selection. It then sets the channel and runs the chosen actions. Every timed action ends in an acknowledged stop. Missing responses, connection loss, unresolvable indices and recognized firmware errors stop the sequence. Stop cancels pending steps; unrelated manual commands are blocked while the sequence runs.

“Attach”/joining Wi-Fi is not part of these actions: the requested meaning and any credential handling still need to be defined. This UI update does not silently connect the ESP32 to an imported network.

## Verified hardware connection

On 17 November 2026, the native app opened `/dev/cu.usbmodemflip_Orwiria1` at 115200 baud through the user's Flipper bridge. The board identified itself as **ESP32 Marauder v1.20.0**, and a `help` request returned its command list. This confirms bidirectional communication through the complete Mac → Flipper → ESP32 path.

During the first connection, the initial `info` request was followed by an ESP32 interrupt-watchdog panic and reboot. The native app remained connected and received the reboot transcript; `help` worked after startup. Automatic `info` was subsequently removed. The board also reported that SD storage and GPS were unavailable. No firmware was flashed, and no attack workflow was run during verification.

After removing automatic `info`, the final build was reconnected through the native UI: connection sent zero bytes, then an explicit `help` request returned 2,091 bytes without a reboot. The app was left open on Networks with the Flipper connected.

The original hardware transcript is in `hardware-verification.txt`. The application now recognizes firmware crash/reboot messages and invalidates old AP selection indices on reboot. The cause of the ESP32 firmware panic has not been diagnosed by this app work.

## Build and check

Apple's Swift Command Line Tools are sufficient; a full Xcode installation and third-party packages are not required.

```sh
./scripts/swift.sh run MarauderChecks
./scripts/build-app.sh
```

All 28 checks passed on this machine, with no skips. The checks cover current/classic parsers, split UTF-8/CRLF input, oversized line recovery, session isolation, duplicate SSIDs, truthful timestamps, out-of-order stations, command validation, workflow rendering, and actual termios/read/write round trips through a pseudo-terminal. A restricted environment may report the pseudo-terminal check as skipped; this machine ran it successfully.

The native UI's automatic sequence was also exercised in demo mode: importing the Workshop record, discovering its exact BSSID, confirming AP selection, reading the AP list, monitoring signal for 15 seconds, and stopping completed successfully. A second run was cancelled during discovery and no subsequent actions ran. These checks simulate firmware responses; the new automatic sequence has not been validated against physical radio activity. Smart quotation marks introduced by macOS are supported by the import parser.

The Swift wrapper redirects compiler caches into `.build` and disables SwiftPM's nested build sandbox, so it can run under restricted development environments. It does not change the Mac's security settings or the runtime app's permissions.

Optional read-only terminal diagnostic:

```sh
./scripts/swift.sh run MarauderProbe                         # list serial ports
./scripts/swift.sh run MarauderProbe /dev/cu.usbmodemNAME    # request help
```

Add `--info` only if you explicitly want to issue `info` as well. The interactive app must be disconnected before using the diagnostic. The build uses the host architecture; build on an Intel Mac for an Intel binary.

## Code map

- `Sources/MarauderCore/Models.swift`: incremental framing, output parsing, BSSID inventory, command validation.
- `Sources/MarauderCore/SerialPort.swift`: nonblocking POSIX serial transport and device discovery.
- `Sources/MarauderCore/Workflows.swift`: declarative workflows and parameter rendering.
- `Sources/MarauderNative/AppModel.swift`: connection/session lifecycle, command history, demo and exports.
- `Sources/MarauderNative/*View.swift`: native UI.
- `Tests/MarauderCoreTests`: dependency-free executable checks; no XCTest installation required.
- `scripts/build-app.sh`: release executable, generated app icon, bundle assembly and signing verification.

## Reference

This is an independent native implementation informed by the behavior of [michelangelomo/marauder-ui](https://github.com/michelangelomo/marauder-ui), not a web wrapper or a port of its Vue source. ESP32 Marauder firmware is maintained by [JustCallMeKoko](https://github.com/justcallmekoko/ESP32Marauder). Connection and command references: [CLI](https://github.com/justcallmekoko/ESP32Marauder/wiki/CLI), [Flipper Zero](https://github.com/justcallmekoko/ESP32Marauder/wiki/Flipper-Zero). The installed device's `help` output is authoritative.
