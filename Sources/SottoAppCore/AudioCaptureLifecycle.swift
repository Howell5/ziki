public enum AudioCaptureLifecycleEvent: Equatable, Sendable {
    case startRequested
    case engineStarted
    case engineStartFailed
    case configurationChanged
    case restartSucceeded
    case restartFailed
    case stopRequested
}

public enum AudioCaptureLifecycleAction: Equatable, Sendable {
    case startEngine
    case releaseEngine
    case scheduleRestart(afterMilliseconds: Int)
    case cancelScheduledRestart
    case reportFailure
}

public struct AudioCaptureLifecycleStateMachine: Sendable {
    private enum State: Sendable {
        case idle
        case starting
        case running(restartAttempts: Int)
        case waitingToRestart(attempt: Int)
    }

    private let maximumRestartAttempts: Int
    private let restartDelayMilliseconds: Int
    private var state: State = .idle

    public init(
        maximumRestartAttempts: Int = 2,
        restartDelayMilliseconds: Int = 180
    ) {
        precondition(maximumRestartAttempts > 0)
        precondition(restartDelayMilliseconds >= 0)
        self.maximumRestartAttempts = maximumRestartAttempts
        self.restartDelayMilliseconds = restartDelayMilliseconds
    }

    @discardableResult
    public mutating func handle(
        _ event: AudioCaptureLifecycleEvent
    ) -> [AudioCaptureLifecycleAction] {
        switch (state, event) {
        case (.idle, .startRequested):
            state = .starting
            return [.startEngine]

        case (.starting, .engineStarted):
            state = .running(restartAttempts: 0)
            return []

        case (.starting, .engineStartFailed):
            state = .idle
            return [.releaseEngine, .reportFailure]

        case let (.running(restartAttempts), .configurationChanged):
            let attempt = restartAttempts + 1
            state = .waitingToRestart(attempt: attempt)
            return [
                .releaseEngine,
                .scheduleRestart(
                    afterMilliseconds: restartDelayMilliseconds
                )
            ]

        case (.waitingToRestart, .configurationChanged):
            return []

        case let (.waitingToRestart(attempt), .restartSucceeded):
            state = .running(restartAttempts: attempt)
            return []

        case let (.waitingToRestart(attempt), .restartFailed):
            guard attempt < maximumRestartAttempts else {
                state = .idle
                return [.releaseEngine, .reportFailure]
            }
            state = .waitingToRestart(attempt: attempt + 1)
            return [
                .releaseEngine,
                .scheduleRestart(
                    afterMilliseconds: restartDelayMilliseconds
                )
            ]

        case (.idle, .stopRequested):
            return []

        case (.waitingToRestart, .stopRequested):
            state = .idle
            return [.cancelScheduledRestart, .releaseEngine]

        case (_, .stopRequested):
            state = .idle
            return [.releaseEngine]

        default:
            return []
        }
    }
}
