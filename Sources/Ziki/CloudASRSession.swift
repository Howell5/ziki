import Foundation
import ZikiCore

private final class CloudNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

actor CloudASRSession: ASRSession {
    nonisolated let inputMode: ASRInputMode = .liveDuplex
    private enum State { case idle, starting, active, finishing, completed, cancelled, failed }
    private let origin: URL
    private let token: String
    private let cleanupEnabled: Bool
    private let context: [DictationContext.Turn]
    private let onLimitReached: @Sendable () -> Void
    private let idempotencyKey = UUID().uuidString.lowercased()
    private let eventPipe = ASREventPipe()
    typealias MetadataRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let metadataRequest: MetadataRequest?
    private let metadataSession: URLSession
    private var releaseTask: Task<Void, Never>?
    private let session: URLSession
    private var state = State.idle
    private var reservation: CloudDictationWire.Reservation?
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var readyWaiter: CheckedContinuation<Void, Error>?
    private var finishWaiters: [CheckedContinuation<Void, Error>] = []
    private var output: CloudDictationResult?
    private var sentBytes = 0
    private var limited = false
    private var terminalError: Error?

    init(origin: URL, token: String, cleanupEnabled: Bool, context: [DictationContext.Turn],
         onLimitReached: @escaping @Sendable () -> Void,
         metadataRequest: MetadataRequest? = nil) {
        self.origin = origin
        self.token = token
        self.cleanupEnabled = cleanupEnabled
        self.context = context
        self.onLimitReached = onLimitReached
        self.metadataRequest = metadataRequest
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 420
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: CloudNoRedirect(), delegateQueue: nil)
        configuration.timeoutIntervalForResource = 30
        metadataSession = URLSession(configuration: configuration, delegate: CloudNoRedirect(), delegateQueue: nil)
    }

    nonisolated func eventStream() -> AsyncThrowingStream<ASREvent, Error> { eventPipe.stream }
    func result() -> CloudDictationResult? { output }

    func start(configuration: ASRConfiguration) async throws {
        guard state == .idle else { throw failure("Cloud 会话已经启动") }
        guard configuration.sampleRate == 16_000,
              origin.scheme == "https" || (AppEnvironment.isDevelopment && origin.scheme == "http" && origin.host == "127.0.0.1"),
              origin.host != nil, origin.user == nil, origin.password == nil,
              origin.query == nil, origin.fragment == nil, origin.path == "" || origin.path == "/",
              !token.isEmpty, !token.contains("\r"), !token.contains("\n"),
              context.count <= 3,
              context.reduce(0, { $0 + $1.rawTranscript.count + $1.polishedTranscript.count }) <= 8_000
        else { throw failure("Cloud 配置无效", kind: .badInput) }
        state = .starting
        do {
            var request = request(path: "/v1/dictations", method: "POST")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["idempotencyKey": idempotencyKey, "maxSeconds": 300])
            let reserved: CloudDictationWire.Reservation
            do {
                let (data, response) = try await boundedRequest(request)
                try check(response)
                reserved = try CloudDictationWire.reservation(data)
            } catch {
                // A lost POST response can hide a committed reservation; replay metadata only.
                await recoverAndRelease(request)
                throw error
            }
            reservation = reserved
            guard state == .starting, !Task.isCancelled else {
                await releaseReservation()
                throw CancellationError()
            }
            var streamRequest = self.request(path: "/v1/dictations/\(reserved.id)/stream", method: "GET")
            var components = URLComponents(url: streamRequest.url!, resolvingAgainstBaseURL: false)!
            components.scheme = origin.scheme == "https" ? "wss" : "ws"
            streamRequest.url = components.url
            let socket = session.webSocketTask(with: streamRequest)
            socket.maximumMessageSize = 524_288
            self.socket = socket
            socket.resume()
            let start: [String: Any] = ["type": "start", "language": configuration.language.rawValue,
                "cleanupEnabled": cleanupEnabled, "context": context.map { ["rawTranscript": $0.rawTranscript, "polishedTranscript": $0.polishedTranscript] }]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: start), as: UTF8.self)
            // Install the waiter before any receive can resume it.
            try await withCheckedThrowingContinuation { continuation in
                readyWaiter = continuation
                armDeadline(seconds: 30)
                receiver = Task { [weak self] in await self?.receiveLoop() }
                Task { [weak self] in
                    do { try await socket.send(.string(json)) }
                    catch { await self?.failTransport() }
                }
            }
        } catch {
            if state == .cancelled { throw CancellationError() }
            let sanitized = (error as? ASRFailure) ?? failure("Cloud 连接失败")
            fail(sanitized)
            throw sanitized
        }
    }

    func sendPCM16(_ data: Data) async throws {
        guard state == .active, let socket, let reservation else { throw terminalError ?? failure("Cloud 会话尚未就绪") }
        if limited || data.isEmpty { return }
        guard data.count % 2 == 0 else { throw failure("Cloud 音频格式无效", kind: .badInput) }
        let count = CloudDictationWire.acceptedBytes(data.count, sent: sentBytes, maximumSeconds: reservation.maxSeconds)
        sentBytes += count
        armDeadline(seconds: 30)
        // The runner awaits each send; no second PCM queue or unbounded send tasks.
        do {
            var offset = 0
            while offset < count {
                guard state == .active else { throw terminalError ?? CancellationError() }
                let end = min(offset + 32_000, count)
                try await socket.send(.data(data.subdata(in: offset..<end)))
                offset = end
            }
            if state == .active { deadline?.cancel(); deadline = nil }
            if sentBytes == reservation.maxSeconds * 32_000, !limited {
                limited = true
                onLimitReached()
            }
        } catch {
            if state == .cancelled { throw CancellationError() }
            let error = failure("Cloud 音频发送失败")
            fail(error)
            throw error
        }
    }

    func finish() async throws {
        if state == .completed { return }
        guard state == .active || state == .finishing else { throw terminalError ?? failure("Cloud 会话无法完成") }
        try await withCheckedThrowingContinuation { continuation in
            finishWaiters.append(continuation)
            guard state == .active, let socket else { return }
            state = .finishing
            armDeadline(seconds: 60)
            Task { [weak self] in
                do { try await socket.send(.string("{\"type\":\"finish\"}")) }
                catch { await self?.failTransport() }
            }
        }
    }

    func cancel() async {
        guard state != .completed, state != .cancelled else { return }
        state = .cancelled
        terminalError = CancellationError()
        close(error: CancellationError())
        eventPipe.continuation.finish()
        await releaseReservation()
    }

    private func receiveLoop() async {
        guard let socket, let reservation else { return }
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case let .string(text): data = Data(text.utf8)
                case let .data(bytes): data = bytes
                @unknown default: throw failure("Cloud 返回了无效响应")
                }
                let event = try CloudDictationWire.event(data, maximumSeconds: reservation.maxSeconds)
                guard state == .starting || state == .active || state == .finishing else { return }
                switch event {
                case .ready:
                    guard state == .starting else { throw failure("Cloud 事件顺序无效") }
                    state = .active
                    deadline?.cancel()
                    let waiter = readyWaiter; readyWaiter = nil
                    waiter?.resume()
                    eventPipe.continuation.yield(.ready)
                case let .hypothesis(text):
                    guard state != .starting else { throw failure("Cloud 事件顺序无效") }
                    eventPipe.continuation.yield(.hypothesis(fullText: text))
                case let .segmentFinal(text):
                    guard state != .starting else { throw failure("Cloud 事件顺序无效") }
                    eventPipe.continuation.yield(.segmentFinal(fullText: text))
                case let .completed(result):
                    guard state == .finishing else { throw failure("Cloud 事件顺序无效") }
                    guard cleanupEnabled && !result.cleanupFailed || result.text == result.rawText else {
                        throw failure("Cloud 整理响应无效")
                    }
                    output = result
                    state = .completed
                    eventPipe.continuation.yield(.completed(fullText: result.rawText, billedSeconds: result.billedSeconds))
                    eventPipe.continuation.finish()
                    close(error: nil)
                    return
                case let .error(code): throw serverFailure(code)
                }
            }
        } catch {
            guard state != .cancelled, state != .completed, state != .failed else { return }
            fail((error as? ASRFailure) ?? failure("Cloud 连接中断"))
        }
    }

    private func request(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: origin.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
        return request
    }

    private func check(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw failure("Cloud 响应无效") }
        guard (200...299).contains(response.statusCode) else {
            switch response.statusCode {
            case 401, 403: throw failure("请重新登录 Cloud", kind: .unauthorized)
            case 402: throw failure("Cloud 可用时长不足", kind: .insufficientBalance)
            case 429: throw failure("Cloud 请求过于频繁", kind: .rateLimited)
            default: throw failure("Cloud 服务暂时不可用")
            }
        }
    }

    private func serverFailure(_ code: String) -> ASRFailure {
        switch code {
        case "unauthorized", "UNAUTHORIZED": return failure("请重新登录 Cloud", kind: .unauthorized)
        case "insufficient_balance", "INSUFFICIENT_BALANCE": return failure("Cloud 可用时长不足", kind: .insufficientBalance)
        default: return ASRFailure(kind: .provider, providerCode: code, message: "Cloud 转写未完成", retryable: false)
        }
    }
    private func failure(_ message: String, kind: ASRFailureKind = .transport) -> ASRFailure {
        ASRFailure(kind: kind, message: message, retryable: false)
    }
    private func failTransport() { fail(failure("Cloud 连接失败")) }
    private func armDeadline(seconds: Int) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            await self?.failTransport()
        }
    }
    private func fail(_ error: ASRFailure) {
        guard state != .completed, state != .cancelled, state != .failed else { return }
        state = .failed
        terminalError = error
        close(error: error)
        eventPipe.continuation.yield(.failed(error))
        eventPipe.continuation.finish()
        Task { await releaseReservation() }
    }
    private func close(error: Error?) {
        deadline?.cancel(); deadline = nil
        receiver?.cancel(); receiver = nil
        socket?.cancel(with: error == nil ? .normalClosure : .goingAway, reason: nil)
        socket = nil
        let ready = readyWaiter; readyWaiter = nil
        if let ready { ready.resume(throwing: error ?? failure("Cloud 会话已关闭")) }
        let waiters = finishWaiters; finishWaiters = []
        for waiter in waiters {
            if let error { waiter.resume(throwing: error) } else { waiter.resume() }
        }
    }
    private func boundedRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if let metadataRequest {
            let result = try await metadataRequest(request)
            guard result.0.count <= 16_384 else { throw failure("Cloud 响应过大") }
            return result
        }
        let (bytes, response) = try await metadataSession.bytes(for: request)
        var data = Data()
        for try await byte in bytes {
            guard data.count < 16_384 else { throw failure("Cloud 响应过大") }
            data.append(byte)
        }
        return (data, response)
    }

    deinit {
        session.invalidateAndCancel()
        metadataSession.invalidateAndCancel()
    }

    private func recoverAndRelease(_ request: URLRequest) async {
        // Unstructured cleanup survives cancellation of the runner awaiting start().
        let recovery = Task { [self] in
            do {
                let (data, response) = try await boundedRequest(request)
                try check(response)
                reservation = try CloudDictationWire.reservation(data)
                await releaseReservation()
            } catch { }
        }
        await recovery.value
    }

    private func releaseReservation() async {
        if let releaseTask { await releaseTask.value; return }
        guard let reservation else { return }
        let cleanup = Task { [self] in
            _ = try? await boundedRequest(request(path: "/v1/dictations/\(reservation.id)/cancel", method: "POST"))
        }
        releaseTask = cleanup
        await cleanup.value
    }
}
