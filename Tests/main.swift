import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
// Captured protocol-format fixtures from the XM5 firmware 2.4.1 reference.
let initFrame: [UInt8] = [0x3E, 0x0C, 0, 0, 0, 0, 2, 0, 0, 0x0E, 0x3C]
check(Message(type: .command1, sequence: 0, payload: [0, 0]).encode() == initFrame, "Sony handshake wire format")
let escaped = Message(type: .command1, sequence: 1, payload: [0x3C, 0x3D, 0x3E])
var parser = FrameParser()
check(parser.feed(Array(escaped.encode().prefix(5))).isEmpty, "Fragment must wait for the rest")
check(parser.feed(Array(escaped.encode().dropFirst(5))) == [escaped], "Escaped fragmented payload must round-trip")
var corrupt = initFrame
corrupt[corrupt.count - 2] ^= 1
check(parser.feed(corrupt).isEmpty, "Reject a corrupt checksum")
check(parser.feed([0xAA, 0x3E, 0x44, 0x01] + initFrame).count == 1, "Resynchronize after an incomplete invalid frame")
let ack = Message(type: .ack, sequence: 1, payload: [])
check(parser.feed(ack.encode() + initFrame).count == 2, "Handle multiple frames in one Bluetooth callback")
check(parser.feed(Array(repeating: 0x99, count: 10000) + initFrame).count == 1, "Bound corrupt stream accumulation and recover")

var state = HeadphoneState()
check(state.percent == nil && state.mode == nil, "Never invent a battery percentage or NC mode")
check(state.apply([0x23, 0, 73, 0]), "Parse a single battery reply")
check(state.percent == 73 && !state.charging, "Battery value")
check(!state.apply([0x23, 0, 255, 1]), "Reject invalid battery values")
check(state.percent == 73, "Malformed replies must not overwrite valid data")
check(state.apply([0x25, 0, 0, 1]), "A valid zero-percent battery is not missing data")
check(state.percent == 0 && state.charging, "Parse charging notification")
check(state.apply([0x67, 0x17, 1, 1, 0, 0, 20]), "Parse NC reply")
check(state.mode == .noiseCancelling, "Decode NC")
check(state.apply([0x69, 0x17, 1, 1, 1, 0, 12]), "Parse ambient notification")
check(state.mode == .ambient && state.ambientLevel == 12, "Decode ambient level")
check(state.apply([0x69, 0x17, 1, 0, 0, 0, 20]) && state.mode == .off, "Decode noise control off")
check(!state.apply([0x67, 0x17, 1, 1, 9, 0, 20]), "Reject unsupported mode instead of guessing NC")
check(!state.apply([0x67, 0x17, 1]), "Reject truncated payload")
check(state.menuBarText(showBattery: true, showMode: true) == "—", "Disconnected state must not show stale percentages or modes")
state.connected = true
check(state.menuBarText(showBattery: true, showMode: true) == "0%ϟ OFF", "Combined menu bar label")
check(state.menuBarText(showBattery: false, showMode: true) == "OFF", "Hide battery independently")
check(state.menuBarText(showBattery: true, showMode: false) == "0%ϟ", "Hide sound mode independently")
check(state.menuBarText(showBattery: false, showMode: false).isEmpty, "Both disabled leaves icon only")

let suite = "nl.local.Logibat.tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let prefs = DisplayPreferences(defaults: defaults)
check(DisplayOption.allCases.allSatisfy(prefs.isEnabled), "Default visibility")
for option in [DisplayOption.keyboard, .mouse, .headphones] { prefs.set(option, enabled: false) }
check(prefs.allDevicesHidden, "All-hidden settings fallback is needed")
let reloaded = DisplayPreferences(defaults: UserDefaults(suiteName: suite)!)
check(reloaded.allDevicesHidden && reloaded.isEnabled(.headphoneMode), "Device and field visibility persist independently")
prefs.set(.headphones, enabled: true)
check(!prefs.allDevicesHidden, "Restoring headphones removes the fallback")
print("Sony framing, payload validation, display labels and persisted visibility checks passed")
