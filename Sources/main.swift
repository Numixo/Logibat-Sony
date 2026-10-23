import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var items: [String: NSStatusItem] = [:]
    private var timer: Timer?
    private var scanning = false
    private var lastScan = ScanResult()
    private var checkedAt: Date?
    private let preferences = DisplayPreferences()
    private let headphones = SonyHeadphones()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "nl.local.Logibat").count <= 1 else {
            NSApp.terminate(nil); return
        }
        headphones.changed = { [weak self] in self?.render() }
        rebuildStatusItems()
        headphones.setEnabled(preferences.isEnabled(.headphones))
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 15
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        headphones.setEnabled(false)
    }

    private func rebuildStatusItems() {
        for item in items.values { NSStatusBar.system.removeStatusItem(item) }
        items.removeAll()
        // Newly inserted items appear on the left: keyboard, mouse, headphones.
        for kind in [DisplayOption.headphones, .mouse, .keyboard] where preferences.isEnabled(kind) {
            makeStatusItem(kind.rawValue)
        }
        // Keep settings reachable even when every device is hidden.
        if preferences.allDevicesHidden { makeStatusItem("settings") }
        render()
    }

    private func makeStatusItem(_ kind: String) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        items[kind] = item
        item.button?.image = kind == "settings" ? nil : deviceIcon(kind)
        item.button?.imagePosition = .imageLeading
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    @objc private func wokeUp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.refresh() }
    }

    @objc private func refresh() {
        headphones.refresh()
        guard !scanning else { return }
        guard preferences.isEnabled(.keyboard) || preferences.isEnabled(.mouse) else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let result = scanBatteries()
            DispatchQueue.main.async {
                self.lastScan = result
                self.checkedAt = Date()
                self.scanning = false
                self.render()
            }
        }
    }

    private func render() {
        for (kind, item) in items {
            if kind == "settings" {
                item.button?.title = "LB"
                item.button?.toolTip = "Logibat · choose devices to show"
                item.button?.setAccessibilityLabel(item.button?.toolTip)
                continue
            }
            if kind == "headphones" {
                let state = headphones.state
                item.button?.title = " " + state.menuBarText(showBattery: preferences.isEnabled(.headphoneBattery), showMode: preferences.isEnabled(.headphoneMode))
                item.button?.contentTintColor = (state.percent ?? 100) <= 15 ? .systemOrange : nil
                let battery = state.percent.map { "\($0)%\(state.charging ? " · charging" : "")" } ?? "Battery unavailable"
                let mode = state.mode?.title ?? "Sound mode unavailable"
                item.button?.toolTip = state.connected ? "\(state.name): \(battery) · \(mode)" : state.status
                item.button?.setAccessibilityLabel(item.button?.toolTip)
                continue
            }
            let reading = lastScan.readings.filter { $0.kind == kind }.min { $0.percent < $1.percent }
            let value = reading.map { "\($0.approximate ? "≈" : "")\($0.percent)%\($0.charging ? "ϟ" : "")" } ?? "—"
            item.button?.title = " " + value
            item.button?.contentTintColor = (reading?.percent ?? 100) <= 15 ? .systemOrange : nil
            item.button?.toolTip = reading.map { "\($0.name): \(value)" } ?? "\(kind == "keyboard" ? "Keyboard" : "Mouse"): no battery data"
            item.button?.setAccessibilityLabel(item.button?.toolTip)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Logibat", action: nil, keyEquivalent: "")
        for reading in lastScan.readings {
            let label = "\(reading.name) · \(reading.approximate ? "≈" : "")\(reading.percent)%\(reading.charging ? " · charging" : "")"
            let row = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            row.image = deviceIcon(reading.kind)
            menu.addItem(row)
        }
        if lastScan.readings.isEmpty, preferences.isEnabled(.keyboard) || preferences.isEnabled(.mouse) {
            menu.addItem(withTitle: lastScan.permissionDenied ? "Logitech access required" : "No active MX devices found", action: nil, keyEquivalent: "")
        }
        if preferences.isEnabled(.headphones) {
            let state = headphones.state
            menu.addItem(.separator())
            let row = NSMenuItem(title: state.name, action: nil, keyEquivalent: "")
            row.image = deviceIcon("headphones")
            menu.addItem(row)
            if state.connected {
                menu.addItem(withTitle: state.percent.map { "Battery: \($0)%\(state.charging ? " · charging" : "")" } ?? "Battery: unavailable", action: nil, keyEquivalent: "")
                let level = state.mode == .ambient ? state.ambientLevel.map { " · level \($0)/20" } ?? "" : ""
                menu.addItem(withTitle: "Sound mode: \(state.mode?.title ?? "unavailable")\(level)", action: nil, keyEquivalent: "")
            } else {
                menu.addItem(withTitle: state.status, action: nil, keyEquivalent: "")
            }
        }
        if let date = checkedAt {
            menu.addItem(withTitle: "MX checked at \(date.formatted(date: .omitted, time: .shortened)) · every 2 minutes", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        let display = NSMenuItem(title: "Show in menu bar", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        displayMenu.autoenablesItems = false
        for option in DisplayOption.allCases {
            if option == .headphoneBattery { displayMenu.addItem(.separator()) }
            let toggle = NSMenuItem(title: option.title, action: #selector(toggleDisplay(_:)), keyEquivalent: "")
            toggle.target = self
            toggle.representedObject = option.rawValue
            toggle.state = preferences.isEnabled(option) ? .on : .off
            displayMenu.addItem(toggle)
        }
        display.submenu = displayMenu
        menu.addItem(display)
        let refreshItem = menu.addItem(withTitle: scanning ? "Reading batteries…" : "Refresh now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = !scanning
        let permission = menu.addItem(withTitle: "Configure Logitech access…", action: #selector(openPermissions), keyEquivalent: "")
        permission.target = self
        let bluetooth = menu.addItem(withTitle: "Bluetooth settings…", action: #selector(openBluetooth), keyEquivalent: "")
        bluetooth.target = self
        let login = menu.addItem(withTitle: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Logibat", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
    }

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let option = DisplayOption(rawValue: raw) else { return }
        preferences.set(option, enabled: !preferences.isEnabled(option))
        // Defer replacing the status item until the menu action has finished.
        DispatchQueue.main.async {
            self.rebuildStatusItems()
            self.headphones.setEnabled(self.preferences.isEnabled(.headphones))
            self.refresh()
        }
    }

    @objc private func openBluetooth() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }

    @objc private func openPermissions() {
        let alert = NSAlert()
        alert.messageText = "Allow Logibat to access your Logitech devices"
        alert.informativeText = "Add Logibat.app under System Settings → Privacy & Security → Input Monitoring and enable it. Then quit and reopen Logibat.\n\nLogibat only reads Logitech battery data through the vendor interface; it does not record keystrokes. Sony headphones use a separate Bluetooth permission, if requested by macOS."
        alert.addButton(withTitle: "Open settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--diagnose-sony") {
    let sony = SonyHeadphones()
    sony.setEnabled(true)
    let end = Date().addingTimeInterval(15)
    while Date() < end && (sony.state.percent == nil || sony.state.mode == nil) {
        CFRunLoopRunInMode(.defaultMode, 0.05, true)
    }
    print(String(data: try JSONEncoder().encode(sony.state), encoding: .utf8)!)
    sony.setEnabled(false)
} else if CommandLine.arguments.contains("--diagnose") {
    let result = scanBatteries()
    print("Interfaces: \(result.interfaces), permission required: \(result.permissionDenied)")
    let data = try JSONEncoder().encode(result.readings)
    print(String(data: data, encoding: .utf8)!)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
