import CoreAudio
import SottoAppCore

enum DefaultAudioInput {
    static func transportKind() -> AudioInputTransportKind {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            0,
            nil,
            &deviceIDSize,
            &deviceID
        ) == noErr,
        deviceID != kAudioObjectUnknown
        else {
            return .builtInOrWired
        }

        var transportType: UInt32 = 0
        var transportTypeSize = UInt32(MemoryLayout<UInt32>.size)
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            deviceID,
            &transportAddress,
            0,
            nil,
            &transportTypeSize,
            &transportType
        ) == noErr
        else {
            return .builtInOrWired
        }

        return transportType == kAudioDeviceTransportTypeBluetooth
            ? .classicBluetooth
            : .builtInOrWired
    }
}
