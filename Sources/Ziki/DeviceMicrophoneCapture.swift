@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Captures PCM from one explicitly chosen input device.
///
/// `AVAudioEngine` records the system default input only. A Bluetooth headset keeps its
/// microphone behind HFP and shares its hardware mute with the output Ziki silences while
/// recording, so a headset microphone can return no audio at all. Recording the Mac's own
/// microphone by device UID leaves the headset an output-only, wideband device and leaves
/// the system default route untouched for other apps.
final class DeviceMicrophoneCapture: NSObject, @unchecked Sendable {
    typealias BufferHandler = @Sendable (AVAudioPCMBuffer) -> Void
    typealias ErrorHandler = @Sendable (Error) -> Void

    enum CaptureError: LocalizedError {
        case deviceUnavailable
        case sessionRejected
        case deviceStopped
        case noAudio

        var errorDescription: String? {
            switch self {
            case .deviceUnavailable: "找不到内建麦克风"
            case .sessionRejected: "无法打开内建麦克风"
            case .deviceStopped: "内建麦克风已停止响应"
            case .noAudio: "内建麦克风没有返回音频"
            }
        }
    }

    private static let logger = Logger(
        subsystem: "com.willhong.sotto",
        category: "microphone"
    )

    private let deviceUID: String
    private let sampleQueue = DispatchQueue(label: "com.ziki.audio.device")
    private let watchdogQueue = DispatchQueue(label: "com.ziki.audio.device.watchdog")
    private let lock = NSLock()
    private var session: AVCaptureSession?
    private var runtimeErrorObserver: NSObjectProtocol?
    private var watchdog: DispatchWorkItem?
    private var deliveredBuffer = false
    private var onBuffer: BufferHandler?
    private var onError: ErrorHandler?

    /// A session that starts successfully can still hand back no audio at all (device held
    /// by another process, driver failure) without raising an error, which would silently
    /// record nothing. The first buffer normally arrives within a few hundred milliseconds.
    private static let firstBufferTimeout: TimeInterval = 1.5

    init(deviceUID: String) {
        self.deviceUID = deviceUID
    }

    func start(onBuffer: @escaping BufferHandler, onError: @escaping ErrorHandler) throws {
        lock.lock()
        self.onBuffer = onBuffer
        self.onError = onError
        lock.unlock()

        guard let device = Self.audioDevice(uniqueID: deviceUID) else {
            throw CaptureError.deviceUnavailable
        }

        let session = AVCaptureSession()
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CaptureError.sessionRejected
        }
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleQueue)

        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CaptureError.sessionRejected
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        let observer = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let failure = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let detail = failure?.localizedDescription ?? "未知错误"
            Self.logger.error("device microphone stopped: \(detail, privacy: .public)")
            self?.report(CaptureError.deviceStopped)
        }

        let work = DispatchWorkItem { [weak self] in
            self?.reportMissingAudio()
        }
        lock.lock()
        deliveredBuffer = false
        watchdog = work
        self.session = session
        runtimeErrorObserver = observer
        lock.unlock()

        watchdogQueue.asyncAfter(
            deadline: .now() + Self.firstBufferTimeout,
            execute: work
        )
        session.startRunning()
    }

    func stop() {
        lock.lock()
        let session = self.session
        let observer = runtimeErrorObserver
        let work = watchdog
        self.session = nil
        runtimeErrorObserver = nil
        watchdog = nil
        onBuffer = nil
        onError = nil
        lock.unlock()

        work?.cancel()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        session?.stopRunning()
    }

    private func reportMissingAudio() {
        lock.lock()
        let shouldReport = session != nil && !deliveredBuffer
        let handler = shouldReport ? onError : nil
        lock.unlock()
        guard let handler else { return }
        Self.logger.error("device microphone returned no audio")
        handler(CaptureError.noAudio)
    }

    private func report(_ error: Error) {
        lock.lock()
        let handler = onError
        lock.unlock()
        handler?(error)
    }

    private static func audioDevice(uniqueID: String) -> AVCaptureDevice? {
        let devices: [AVCaptureDevice]
        if #available(macOS 14.0, *) {
            devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            ).devices
        } else {
            // ponytail: macOS 13 has no non-deprecated audio discovery; drop the
            // fallback when the app targets macOS 14.
            devices = AVCaptureDevice.devices(for: .audio)
        }
        return devices.first { $0.uniqueID == uniqueID }
    }

    /// Reinterprets one captured sample buffer as float PCM without copying twice.
    private func makeBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else { return nil }

        let channels = Int(stream.pointee.mChannelsPerFrame)
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard stream.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              channels > 0,
              frames > 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: stream.pointee.mSampleRate,
                  channels: AVAudioChannelCount(channels),
                  interleaved: stream.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frames)
              ),
              let block = CMSampleBufferGetDataBuffer(sampleBuffer)
        else { return nil }

        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &pointer
        ) == noErr, let pointer else { return nil }

        buffer.frameLength = AVAudioFrameCount(frames)
        let destinations = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let sourceFloats = length / MemoryLayout<Float>.size
        pointer.withMemoryRebound(to: Float.self, capacity: sourceFloats) { samples in
            if format.isInterleaved {
                guard let destination = destinations[0].mData else { return }
                memcpy(destination, samples, min(length, frames * channels * MemoryLayout<Float>.size))
            } else {
                let bytesPerChannel = frames * MemoryLayout<Float>.size
                for channel in 0..<min(channels, destinations.count) {
                    guard let destination = destinations[channel].mData else { continue }
                    memcpy(destination, samples.advanced(by: channel * frames), bytesPerChannel)
                }
            }
        }
        return buffer
    }
}

extension DeviceMicrophoneCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = makeBuffer(from: sampleBuffer) else { return }
        lock.lock()
        deliveredBuffer = true
        let handler = onBuffer
        lock.unlock()
        handler?(buffer)
    }
}
