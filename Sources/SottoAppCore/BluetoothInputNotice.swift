public enum AudioInputTransportKind: Equatable, Sendable {
    case classicBluetooth
    case builtInOrWired
}

public enum BluetoothInputNotice {
    public static func resolve(
        for transport: AudioInputTransportKind
    ) -> String? {
        switch transport {
        case .classicBluetooth:
            "蓝牙麦克风会暂时降低耳机播放音质"
        case .builtInOrWired:
            nil
        }
    }
}
