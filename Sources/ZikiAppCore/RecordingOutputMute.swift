import Combine
import CoreAudio
import Foundation

/// Owns only the mute changes made for one recording. Never changes volume or playback.
@MainActor
public final class RecordingOutputMute: ObservableObject {
    @Published public private(set) var notice: String?
    @Published public private(set) var hasPendingRecovery: Bool

    private static let recoveryKey = "recordingOutputMuteRecoveryUIDs"
    private let defaults: UserDefaults
    private let currentDevice: () -> String?
    private let readMute: (String) -> Bool?
    private let writeMute: (String, Bool) -> Bool
    private let observeHardware: Bool
    private var listener: AudioObjectPropertyListenerBlock?
    private var active = false
    private var mutingEnabled = false
    private var generation = 0
    private var lastDevice: String?
    private var owned = Set<String>()
    private var pending: Set<String>

    public convenience init() {
        self.init(defaults: .standard)
    }

    public convenience init(defaults: UserDefaults) {
        self.init(
            defaults: defaults,
            currentDevice: OutputMuteHardware.currentDeviceUID,
            readMute: OutputMuteHardware.readMute,
            writeMute: OutputMuteHardware.writeMute,
            observeHardware: true
        )
    }

    /// Injectable hardware operations keep failure/route tests independent of real speakers.
    public init(
        defaults: UserDefaults,
        currentDevice: @escaping () -> String?,
        readMute: @escaping (String) -> Bool?,
        writeMute: @escaping (String, Bool) -> Bool,
        observeHardware: Bool = false
    ) {
        self.defaults = defaults
        self.currentDevice = currentDevice
        self.readMute = readMute
        self.writeMute = writeMute
        self.observeHardware = observeHardware
        pending = Set(defaults.stringArray(forKey: Self.recoveryKey) ?? [])
        hasPendingRecovery = !pending.isEmpty
    }

    public func start(enabled: Bool, recording: () throws -> Void) throws {
        precondition(!active, "Recording is already active")
        active = true
        mutingEnabled = enabled
        generation += 1
        notice = nil
        if enabled {
            if observeHardware { installListener() }
            outputDeviceChanged()
        }
        do {
            try recording()
        } catch {
            finish()
            throw error
        }
    }

    public func stop<T>(recording: () -> T) -> T {
        // Release the microphone before allowing sound back out, including on cancellation.
        defer { finish() }
        return recording()
    }

    public func outputDeviceChanged() {
        guard active && mutingEnabled else { return }
        let next = currentDevice()
        guard next != lastDevice || next == nil else { return }
        lastDevice = next
        if let next {
            if let muted = readMute(next) {
                if !muted {
                    // Persist BEFORE changing hardware, so a crash cannot lose restoration intent.
                    pending.insert(next)
                    persist()
                    owned.insert(next)
                    if !writeMute(next, true) || readMute(next) != true {
                        notice = "无法静音当前输出设备，请手动静音"
                        restore(next)
                    }
                }
            } else {
                notice = "当前输出设备不支持自动静音，请手动静音"
            }
        } else {
            notice = "无法读取声音输出设备，请手动检查静音"
        }
        // Mute the new route first, then release the old route. A disconnected device
        // keeps its stable UID in the recovery journal, never its recyclable numeric ID.
        for uid in owned where uid != next { restore(uid) }
    }

    public func recoverPending() {
        guard !active else { return }
        notice = nil
        for uid in pending { restore(uid) }
    }

    private func finish() {
        active = false
        generation += 1
        removeListener()
        lastDevice = nil
        for uid in owned { restore(uid) }
        owned.removeAll()
    }

    private func restore(_ uid: String) {
        // If the user already unmuted, do nothing. Volume adjustments are always kept.
        guard let muted = readMute(uid) else {
            notice = "部分输出设备尚未恢复，请连接设备后在语音设置中恢复声音"
            return
        }
        if muted && (!writeMute(uid, false) || readMute(uid) != false) {
            notice = "声音恢复失败，请在语音设置中重试或手动解除静音"
            return
        }
        owned.remove(uid)
        pending.remove(uid)
        persist()
    }

    private func persist() {
        defaults.set(pending.sorted(), forKey: Self.recoveryKey)
        // This tiny journal is a recovery boundary, not per-audio-buffer telemetry.
        defaults.synchronize()
        hasPendingRecovery = !pending.isEmpty
    }

    private func installListener() {
        let expectedGeneration = generation
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == expectedGeneration else { return }
                self.outputDeviceChanged()
            }
        }
        var address = OutputMuteHardware.defaultOutputAddress
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, block
        ) == noErr {
            listener = block
        } else {
            notice = "无法监听输出设备切换；录音时请勿切换耳机"
        }
    }

    private func removeListener() {
        guard let listener else { return }
        var address = OutputMuteHardware.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener
        )
        self.listener = nil
    }
}

private enum OutputMuteHardware {
    static var defaultOutputAddress: AudioObjectPropertyAddress {
        .init(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static var muteAddress: AudioObjectPropertyAddress {
        .init(mSelector: kAudioDevicePropertyMute,
              mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    static func currentDeviceUID() -> String? {
        var address = defaultOutputAddress
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
            0, nil, &size, &device) == noErr, device != kAudioObjectUnknown else { return nil }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        return status == noErr ? uid as String : nil
    }

    private static func deviceID(_ uid: String) -> AudioDeviceID? {
        var address = defaultOutputAddress
        address.mSelector = kAudioHardwarePropertyTranslateUIDToDevice
        var identifier = uid as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &identifier) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func readMute(_ uid: String) -> Bool? {
        guard let device = deviceID(uid) else { return nil }
        var address = muteAddress
        // ponytail: only device-wide mute; channel-only/HDMI devices report unsupported.
        // Add per-channel snapshots when a real supported-device case requires them.
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    static func writeMute(_ uid: String, _ mute: Bool) -> Bool {
        guard let device = deviceID(uid) else { return false }
        var address = muteAddress
        var value: UInt32 = mute ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
