import CoreAudio
import Foundation

public enum AudioInputTransportKind: Equatable, Sendable {
    case classicBluetooth
    case builtInOrWired
}

/// Chooses the microphone one recording captures from.
///
/// A classic Bluetooth headset exposes its microphone only through HFP: the whole
/// headset link drops to narrowband playback for as long as Ziki captures, and the
/// headset mute Ziki writes before capturing can silence the headset's own microphone,
/// which then records no audio at all. The Mac's built-in microphone avoids both, and
/// selecting it leaves the system default route untouched for other apps.
public enum AudioInputRoute {
    /// Device UID to capture from, or nil to keep the system default input.
    public static func captureDeviceUID() -> String? {
        let transport = defaultInputTransportKind()
        // The built-in microphone only matters for a Bluetooth headset, so every other
        // dictation skips the device scan and any third-party driver it touches.
        guard transport == .classicBluetooth else { return nil }
        return preferredDeviceUID(
            defaultInput: transport,
            builtInMicrophoneUID: builtInMicrophoneUID()
        )
    }

    public static func preferredDeviceUID(
        defaultInput: AudioInputTransportKind,
        builtInMicrophoneUID: String?
    ) -> String? {
        defaultInput == .classicBluetooth ? builtInMicrophoneUID : nil
    }

    public static func defaultInputTransportKind() -> AudioInputTransportKind {
        guard let device = AudioInputHardware.defaultInputDeviceID() else {
            return .builtInOrWired
        }
        return AudioInputHardware.transportType(device) == kAudioDeviceTransportTypeBluetooth
            ? .classicBluetooth
            : .builtInOrWired
    }

    public static func builtInMicrophoneUID() -> String? {
        for device in AudioInputHardware.allDeviceIDs()
        where AudioInputHardware.inputChannelCount(device) > 0 {
            guard AudioInputHardware.transportType(device) == kAudioDeviceTransportTypeBuiltIn,
                  let uid = AudioInputHardware.deviceUID(device)
            else { continue }
            return uid
        }
        return nil
    }
}

private enum AudioInputHardware {
    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func transportType(_ device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    static func deviceUID(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        return status == noErr ? uid as String : nil
    }

    static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }
        var devices = [AudioDeviceID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }
        return devices.filter { $0 != kAudioObjectUnknown }
    }

    static func inputChannelCount(_ device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        let buffers = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
