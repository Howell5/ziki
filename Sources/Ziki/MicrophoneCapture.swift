@preconcurrency import AVFoundation
import Accelerate
import Foundation
import OSLog
import ZikiAppCore

enum MicrophoneCaptureError: LocalizedError {
    case unavailable
    case conversionUnavailable
    case conversionFailed(String)
    case configurationChanged
    case maximumDurationReached

    var errorDescription: String? {
        switch self {
        case .unavailable: "没有可用的麦克风输入"
        case .conversionUnavailable: "无法创建 16 kHz 音频转换器"
        case let .conversionFailed(message): "音频转换失败：\(message)"
        case .configurationChanged: "录音时麦克风设备发生了变化"
        case .maximumDurationReached: "录音时间超过安全上限"
        }
    }
}

private final class PCMBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

// AVAudioConverter invokes its input block synchronously, but Swift 6 treats
// the block as potentially concurrent. Keeping the one-shot state in an
// explicitly sendable reference avoids capturing and mutating a local var.
private final class ConverterInputState: @unchecked Sendable {
    var consumed = false
}

private final class ConverterEndState: @unchecked Sendable {
    var signalledEnd = false
}

final class MicrophoneCapture: @unchecked Sendable {
    typealias PCMCallback = @Sendable (Data) -> Void
    typealias LevelCallback = @Sendable (Double) -> Void
    typealias ErrorCallback = @Sendable (Error) -> Void

    private static let logger = Logger(
        subsystem: "com.willhong.sotto",
        category: "microphone"
    )

    private let lifecycleQueue = DispatchQueue(
        label: "com.ziki.audio.lifecycle"
    )
    private let processingQueue = DispatchQueue(label: "com.ziki.audio.convert")
    private let tapCallbackGroup = DispatchGroup()
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var inputTapInstalled = false
    private var deviceCapture: DeviceMicrophoneCapture?
    /// Resolved once per recording so a mid-recording route change cannot move
    /// capture onto a headset microphone.
    private var captureDeviceUID: String?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var capturedPCM = Data()
    private var onPCM: PCMCallback?
    private var onLevel: LevelCallback?
    private var onError: ErrorCallback?
    private var isRunning = false
    private var captureGeneration = 0
    private var didReportMaximumDuration = false
    private var configurationObserver: NSObjectProtocol?
    private var scheduledRestart: DispatchWorkItem?
    private var lifecycle = AudioCaptureLifecycleStateMachine()
    private var lastRestartError: Error?
    // Provider-aware timers stop normally at 3/5 minutes. This is only a
    // hard safety ceiling if coordinator state is disrupted.
    private let maximumPCMBytes = 16_000 * 2 * 60 * 6

    func start(
        onPCM: @escaping PCMCallback,
        onLevel: @escaping LevelCallback,
        onError: @escaping ErrorCallback
    ) throws {
        // Resolved before locking: CoreAudio device queries must not run while the
        // capture callback thread waits on this lock.
        let selectedDeviceUID = AudioInputRoute.captureDeviceUID()
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        captureGeneration &+= 1
        let generation = captureGeneration
        self.onPCM = onPCM
        self.onLevel = onLevel
        self.onError = onError
        captureDeviceUID = selectedDeviceUID
        lock.unlock()

        processingQueue.sync {
            self.capturedPCM.removeAll(keepingCapacity: true)
            self.didReportMaximumDuration = false
        }

        let startError: Error? = lifecycleQueue.sync {
            guard lifecycle.handle(.startRequested) == [.startEngine] else {
                return MicrophoneCaptureError.unavailable
            }
            do {
                try startCapture(generation: generation)
                _ = lifecycle.handle(.engineStarted)
                return nil
            } catch {
                let actions = lifecycle.handle(.engineStartFailed)
                executeLifecycleActions(
                    actions,
                    generation: generation,
                    reportFailure: false
                )
                return error
            }
        }

        if let startError {
            processingQueue.sync {
                converter = nil
                outputFormat = nil
                capturedPCM.removeAll(keepingCapacity: true)
            }
            resetRunningState()
            throw startError
        }
    }

    func stop() -> Data {
        lock.lock()
        isRunning = false
        captureGeneration &+= 1
        lock.unlock()

        lifecycleQueue.sync {
            executeLifecycleActions(
                lifecycle.handle(.stopRequested),
                generation: nil,
                reportFailure: false
            )
        }

        // A tap callback that already began may not have queued its copied
        // buffer yet. Wait for those callbacks before placing the conversion
        // barrier, otherwise the final hardware buffer can land behind it.
        tapCallbackGroup.wait()

        let data = processingQueue.sync { () -> Data in
            drainConverterEndOfStream()
            let result = capturedPCM
            capturedPCM.removeAll(keepingCapacity: true)
            converter = nil
            outputFormat = nil
            return result
        }

        lock.lock()
        onPCM = nil
        onLevel = nil
        onError = nil
        lock.unlock()
        return data
    }

    private func startCapture(generation: Int) throws {
        guard isActive(generation: generation) else {
            throw CancellationError()
        }

        guard let captureDeviceUID else {
            try startEngineCapture(generation: generation)
            return
        }

        // A chosen device carries its own sample rate, so the converter is built
        // from the first captured buffer instead of the engine's input format.
        let capture = DeviceMicrophoneCapture(deviceUID: captureDeviceUID)
        try capture.start(
            onBuffer: { [weak self] buffer in
                self?.receiveTap(buffer)
            },
            onError: { [weak self] error in
                self?.callbackSnapshot().error?(error)
            }
        )
        deviceCapture = capture
    }

    private func startEngineCapture(generation: Int) throws {
        let nextEngine = AVAudioEngine()
        let input = nextEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw MicrophoneCaptureError.unavailable
        }
        guard let prepared = Self.makeConverter(from: inputFormat) else {
            throw MicrophoneCaptureError.conversionUnavailable
        }

        processingQueue.sync {
            self.outputFormat = prepared.outputFormat
            self.converter = prepared.converter
        }

        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nextEngine,
            queue: nil
        ) { [weak self, weak nextEngine] _ in
            guard let nextEngine else { return }
            self?.enqueueConfigurationChange(
                for: nextEngine,
                generation: generation
            )
        }

        input.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: nil
        ) { [weak self] buffer, _ in
            self?.receiveTap(buffer)
        }

        engine = nextEngine
        inputTapInstalled = true
        configurationObserver = observer

        do {
            nextEngine.prepare()
            try nextEngine.start()
        } catch {
            releaseEngine()
            throw error
        }
    }

    private func enqueueConfigurationChange(
        for changedEngine: AVAudioEngine,
        generation: Int
    ) {
        lifecycleQueue.async { [weak self, weak changedEngine] in
            guard let self,
                  let changedEngine,
                  self.engine === changedEngine,
                  self.isActive(generation: generation)
            else { return }

            Self.logger.info(
                "Audio hardware configuration changed; restarting capture"
            )
            self.executeLifecycleActions(
                self.lifecycle.handle(.configurationChanged),
                generation: generation,
                reportFailure: true
            )
        }
    }

    private func executeLifecycleActions(
        _ actions: [AudioCaptureLifecycleAction],
        generation: Int?,
        reportFailure: Bool
    ) {
        for action in actions {
            switch action {
            case .startEngine:
                break

            case .releaseEngine:
                releaseEngine()

            case let .scheduleRestart(afterMilliseconds):
                guard let generation else { continue }
                scheduleRestart(
                    afterMilliseconds: afterMilliseconds,
                    generation: generation
                )

            case .cancelScheduledRestart:
                scheduledRestart?.cancel()
                scheduledRestart = nil

            case .reportFailure:
                guard reportFailure else { continue }
                let error = lastRestartError
                    ?? MicrophoneCaptureError.configurationChanged
                callbackSnapshot().error?(error)
            }
        }
    }

    private func scheduleRestart(
        afterMilliseconds: Int,
        generation: Int
    ) {
        scheduledRestart?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduledRestart = nil
            guard self.isActive(generation: generation) else {
                self.executeLifecycleActions(
                    self.lifecycle.handle(.stopRequested),
                    generation: nil,
                    reportFailure: false
                )
                return
            }

            do {
                try self.startCapture(generation: generation)
                self.lastRestartError = nil
                self.executeLifecycleActions(
                    self.lifecycle.handle(.restartSucceeded),
                    generation: generation,
                    reportFailure: true
                )
            } catch {
                self.lastRestartError = error
                Self.logger.error(
                    "Audio capture restart failed: \(error.localizedDescription, privacy: .public)"
                )
                self.executeLifecycleActions(
                    self.lifecycle.handle(.restartFailed),
                    generation: generation,
                    reportFailure: true
                )
            }
        }
        scheduledRestart = workItem
        lifecycleQueue.asyncAfter(
            deadline: .now() + .milliseconds(afterMilliseconds),
            execute: workItem
        )
    }

    private func releaseEngine() {
        if let deviceCapture {
            deviceCapture.stop()
            self.deviceCapture = nil
        }

        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }

        if let engine {
            if inputTapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                inputTapInstalled = false
            }
            engine.stop()
            engine.reset()
            self.engine = nil
        }

        tapCallbackGroup.wait()
    }

    private func isActive(generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning && captureGeneration == generation
    }

    private func receiveTap(_ buffer: AVAudioPCMBuffer) {
        tapCallbackGroup.enter()
        defer { tapCallbackGroup.leave() }

        lock.lock()
        let shouldAcceptBuffer = isRunning
        lock.unlock()
        guard shouldAcceptBuffer else { return }

        let callbacks = callbackSnapshot()
        if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
            let normalized = min(1, max(0, Double(rms) * 8))
            callbacks.level?(normalized)
        }

        guard let copy = copyBuffer(buffer) else { return }
        let box = PCMBufferBox(copy)
        processingQueue.async { [weak self, box] in
            self?.convert(box.buffer)
        }
    }

    private func convert(_ input: AVAudioPCMBuffer) {
        if converter == nil || outputFormat == nil {
            // A device capture reports its format with the first buffer.
            guard let prepared = Self.makeConverter(from: input.format) else {
                callbackSnapshot().error?(MicrophoneCaptureError.conversionUnavailable)
                return
            }
            converter = prepared.converter
            outputFormat = prepared.outputFormat
        }
        guard let converter, let outputFormat else { return }
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 32
        guard let output = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else { return }

        let inputState = ConverterInputState()
        var conversionError: NSError?
        let status = converter.convert(
            to: output,
            error: &conversionError
        ) { _, inputStatus in
            if inputState.consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputState.consumed = true
            inputStatus.pointee = .haveData
            return input
        }

        guard status != .error,
              conversionError == nil,
              output.frameLength > 0,
              let samples = output.int16ChannelData?[0]
        else {
            let message = conversionError?.localizedDescription ?? "unknown converter status"
            callbackSnapshot().error?(MicrophoneCaptureError.conversionFailed(message))
            return
        }

        let byteCount = Int(output.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: samples, count: byteCount)
        deliver(data)
    }

    private func drainConverterEndOfStream() {
        guard let converter, let outputFormat else { return }
        let endState = ConverterEndState()

        for _ in 0..<8 {
            guard let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: 256
            ) else { return }

            var conversionError: NSError?
            let status = converter.convert(
                to: output,
                error: &conversionError
            ) { _, inputStatus in
                if endState.signalledEnd {
                    inputStatus.pointee = .noDataNow
                } else {
                    endState.signalledEnd = true
                    inputStatus.pointee = .endOfStream
                }
                return nil
            }

            if output.frameLength > 0, let samples = output.int16ChannelData?[0] {
                let byteCount = Int(output.frameLength) * MemoryLayout<Int16>.size
                deliver(Data(bytes: samples, count: byteCount))
            }

            if status == .error {
                let message = conversionError?.localizedDescription
                    ?? "unknown converter drain status"
                callbackSnapshot().error?(MicrophoneCaptureError.conversionFailed(message))
                return
            }
            if status == .endOfStream || output.frameLength == 0 {
                return
            }
        }
    }

    private func deliver(_ data: Data) {
        if capturedPCM.count + data.count <= maximumPCMBytes {
            capturedPCM.append(data)
            callbackSnapshot().pcm?(data)
        } else if !didReportMaximumDuration {
            didReportMaximumDuration = true
            callbackSnapshot().error?(MicrophoneCaptureError.maximumDurationReached)
        }
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameLength
        ) else { return nil }
        copy.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (source, destination) in zip(sourceBuffers, destinationBuffers) {
            guard let sourceData = source.mData, let destinationData = destination.mData else {
                continue
            }
            memcpy(destinationData, sourceData, Int(source.mDataByteSize))
        }
        return copy
    }

    private static func makeConverter(
        from inputFormat: AVAudioFormat
    ) -> (converter: AVAudioConverter, outputFormat: AVAudioFormat)? {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(
            from: inputFormat,
            to: outputFormat
        ) else { return nil }
        return (converter, outputFormat)
    }

    private func callbackSnapshot() -> (
        pcm: PCMCallback?,
        level: LevelCallback?,
        error: ErrorCallback?
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (onPCM, onLevel, onError)
    }

    private func resetRunningState() {
        lock.lock()
        isRunning = false
        onPCM = nil
        onLevel = nil
        onError = nil
        lock.unlock()
    }
}
