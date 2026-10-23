import Foundation

enum SoundMode: String, Codable {
    case noiseCancelling = "NC"
    case ambient = "AMB"
    case off = "OFF"
    var title: String {
        switch self {
        case .noiseCancelling: return "Noise cancelling"
        case .ambient: return "Ambient sound"
        case .off: return "Noise control off"
        }
    }
}

struct HeadphoneState: Codable {
    var connected = false
    var name = "WH-1000XM5"
    var percent: Int?
    var charging = false
    var mode: SoundMode?
    var ambientLevel: Int?
    var status = "Not connected"

    // Sony MDR v2 read replies and notifications, restricted to the XM5 fields we use.
    mutating func apply(_ payload: [UInt8]) -> Bool {
        guard payload.count >= 2 else { return false }
        switch payload[0] {
        case 0x23, 0x25:
            guard payload.count == 4, payload[1] == 0, payload[2] <= 100, payload[3] <= 1 else { return false }
            percent = Int(payload[2])
            charging = payload[3] == 1
            return true
        case 0x67, 0x69:
            guard payload.count == 7, [0x15, 0x17].contains(payload[1]),
                  payload[3] <= 1, payload[4] <= 1, payload[6] <= 20 else { return false }
            mode = payload[3] == 0 ? .off : (payload[4] == 0 ? .noiseCancelling : .ambient)
            ambientLevel = Int(payload[6])
            return true
        default: return false
        }
    }

    func menuBarText(showBattery: Bool, showMode: Bool) -> String {
        guard connected else { return "—" }
        var parts: [String] = []
        if showBattery { parts.append(percent.map { "\($0)%\(charging ? "ϟ" : "")" } ?? "—%") }
        if showMode { parts.append(mode?.rawValue ?? "—") }
        return parts.joined(separator: " ")
    }
}

enum DisplayOption: String, CaseIterable {
    case keyboard, mouse, headphones, headphoneBattery, headphoneMode
    var title: String {
        switch self {
        case .keyboard: return "Keyboard"
        case .mouse: return "Mouse"
        case .headphones: return "Sony WH-1000XM5"
        case .headphoneBattery: return "Headphone battery percentage"
        case .headphoneMode: return "Headphone sound mode (NC / AMB / OFF)"
        }
    }
}

struct DisplayPreferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func isEnabled(_ option: DisplayOption) -> Bool {
        defaults.object(forKey: "display.\(option.rawValue)") as? Bool ?? true
    }
    func set(_ option: DisplayOption, enabled: Bool) {
        defaults.set(enabled, forKey: "display.\(option.rawValue)")
    }
    var allDevicesHidden: Bool {
        ![DisplayOption.keyboard, .mouse, .headphones].contains(where: isEnabled)
    }
}
