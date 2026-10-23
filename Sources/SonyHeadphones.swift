import Foundation
import IOBluetooth

// Read-only Sony MDR v2 client. Protocol reference: sbtfix/docs/PROTOCOL.md.
// All Bluetooth callbacks and state access run on the main run loop.
final class SonyHeadphones: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private(set) var state = HeadphoneState()
    var changed: (() -> Void)?
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var parser = FrameParser()
    private var sequence: UInt8 = 0
    private var pending = false
    private var queue: [[UInt8]] = []
    private var initialized = false
    private var enabled = false
    private var connecting = false
    private var retryTimer: Timer?
    private var ackTimer: Timer?
    private var connectTimer: Timer?
    private var refreshTimer: Timer?
    private var connectNotice: IOBluetoothUserNotification?
    private var disconnectNotice: IOBluetoothUserNotification?
    private var batteryDate: Date?
    private var modeDate: Date?
    private let serviceUUID = IOBluetoothSDPUUID(bytes: [UInt8](
        [0x95, 0x6C, 0x7B, 0x26, 0xD4, 0x9A, 0x4B, 0xA8, 0xB0, 0x3F, 0xB1, 0x7D, 0x39, 0x3C, 0xB6, 0xE2]), length: 16)

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value {
            connectNotice = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
            retryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.connect() }
            retryTimer?.tolerance = 5
            connect()
        } else {
            retryTimer?.invalidate(); retryTimer = nil
            connectNotice?.unregister(); connectNotice = nil
            reset("Headphone monitoring disabled")
        }
    }

    func refresh() {
        guard initialized, channel != nil else { connect(); return }
        expireReadings()
        enqueue([0x22, 0x00]) // Single battery, not earbuds/case.
        enqueue([0x66, 0x17]) // WH-1000XM5 noise control.
    }

    private func connect() {
        guard enabled, channel == nil, !connecting else { return }
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        guard let target = paired.first(where: { ($0.name ?? "").uppercased() == "WH-1000XM5" && $0.isConnected() }) else {
            state = HeadphoneState()
            state.status = "Connect your WH-1000XM5 in Bluetooth settings"
            changed?()
            return
        }
        device = target
        state.name = target.name ?? "WH-1000XM5"
        connecting = true
        state.status = "Connecting to Sony control service…"
        changed?()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            self?.reset("Sony control connection timed out; will retry")
        }
        if let id = channelID(target) { open(id) }
        else {
            let result = target.performSDPQuery(self, uuids: [serviceUUID])
            if result != kIOReturnSuccess { reset("Could not discover Sony control service") }
        }
    }

    private func channelID(_ target: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        guard let record = target.getServiceRecord(for: serviceUUID) else { return nil }
        var id: BluetoothRFCOMMChannelID = 0
        return record.getRFCOMMChannelID(&id) == kIOReturnSuccess ? id : nil
    }

    @objc func sdpQueryComplete(_ target: IOBluetoothDevice!, status: IOReturn) {
        guard connecting, enabled, target == device, let target else { return }
        if let id = channelID(target) { open(id) }
        else { reset("Sony control service is unavailable") }
    }

    private func open(_ id: BluetoothRFCOMMChannelID) {
        guard let device else { return }
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: id, delegate: self)
        if result == kIOReturnSuccess { channel = opened }
        else { reset(String(format: "Sony access unavailable (0x%08x)", result)) }
    }

    @objc private func deviceConnected(_ notice: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard (device.name ?? "").uppercased() == "WH-1000XM5" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.connect() }
    }

    @objc private func deviceDisconnected(_ notice: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        reset("Headphones disconnected")
    }

    private func reset(_ reason: String) {
        connectTimer?.invalidate(); connectTimer = nil
        ackTimer?.invalidate(); ackTimer = nil
        refreshTimer?.invalidate(); refreshTimer = nil
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        device = nil
        disconnectNotice?.unregister(); disconnectNotice = nil
        parser = FrameParser()
        queue.removeAll()
        pending = false
        initialized = false
        connecting = false
        sequence = 0
        batteryDate = nil; modeDate = nil
        state = HeadphoneState()
        state.status = reason
        changed?()
    }

    private func enqueue(_ payload: [UInt8]) {
        if !queue.contains(payload) { queue.append(payload) }
        pump()
    }

    private func pump() {
        guard channel != nil, !pending, !queue.isEmpty else { return }
        let payload = queue.removeFirst()
        pending = true
        ackTimer?.invalidate()
        ackTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            // A lost ACK makes the sequence uncertain. Reconnect instead of sending stale commands.
            self?.reset("Sony query timed out; will retry")
        }
        write(Message(type: .command1, sequence: sequence, payload: payload).encode())
    }

    private func write(_ bytes: [UInt8]) {
        guard let channel else { return }
        if CommandLine.arguments.contains("--sony-trace") { print("Sony TX", bytes.map { String(format: "%02X", $0) }.joined()) }
        var data = bytes
        let result = data.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
        if result != kIOReturnSuccess { reset("Sony control channel write failed") }
    }

    private func expireReadings() {
        if batteryDate.map({ Date().timeIntervalSince($0) > 300 }) ?? false { state.percent = nil; state.charging = false }
        if modeDate.map({ Date().timeIntervalSince($0) > 300 }) ?? false { state.mode = nil; state.ambientLevel = nil }
        changed?()
    }

    func rfcommChannelOpenComplete(_ opened: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard enabled, connecting else { opened?.close(); return }
        guard error == kIOReturnSuccess else { reset("Sony control channel could not open"); return }
        channel = opened
        disconnectNotice = device?.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // Bluetooth audio can settle before the control service accepts its first command.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.channel === opened else { return }
            self.enqueue([0x00, 0x00])
        }
    }

    func rfcommChannelData(_ source: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length count: Int) {
        guard let pointer, count > 0, source === channel else { return }
        let bytes = Array(UnsafeRawBufferPointer(start: pointer, count: count))
        for message in parser.feed(bytes) {
            if CommandLine.arguments.contains("--sony-trace") { print("Sony RX", message.payload.map { String(format: "%02X", $0) }.joined()) }
            if message.type == .ack {
                guard pending, message.sequence <= 1 else { continue }
                sequence = message.sequence
                pending = false
                ackTimer?.invalidate(); ackTimer = nil
                pump()
            } else {
                guard message.sequence <= 1 else { continue }
                write(Message(type: .ack, sequence: 1 - message.sequence, payload: []).encode())
                guard channel != nil else { return }
                if message.payload.first == 0x01, !initialized {
                    guard message.payload.count == 8 else { reset("This Sony protocol version is unsupported"); return }
                    initialized = true
                    connecting = false
                    connectTimer?.invalidate(); connectTimer = nil
                    state.connected = true
                    state.status = "Connected"
                    changed?()
                    refresh()
                    refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.refresh() }
                    refreshTimer?.tolerance = 10
                } else if initialized, state.apply(message.payload) {
                    if [0x23, 0x25].contains(message.payload[0]) { batteryDate = Date() }
                    if [0x67, 0x69].contains(message.payload[0]) { modeDate = Date() }
                    changed?()
                }
            }
        }
    }

    func rfcommChannelClosed(_ closed: IOBluetoothRFCOMMChannel!) {
        guard closed === channel else { return }
        reset("Headphones disconnected")
    }
}
