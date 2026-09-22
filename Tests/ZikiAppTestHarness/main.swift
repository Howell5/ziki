import Darwin
import CoreAudio
import Foundation
import ZikiAppCore

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect<T: Equatable>(
    _ actual: T,
    equals expected: T,
    _ message: String
) throws {
    guard actual == expected else {
        throw TestFailure(
            description: "\(message): expected \(expected), got \(actual)"
        )
    }
}

@MainActor
private final class EventRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }
}

@MainActor
private final class FakeHistoryRecorder: DictationHistoryRecording {
    var result = true
    private(set) var receivedText: String?
    private(set) var receivedProviderID: String?
    private let events: EventRecorder

    init(events: EventRecorder) {
        self.events = events
    }

    @discardableResult
    func append(text: String, providerID: String) -> Bool {
        events.record("history")
        receivedText = text
        receivedProviderID = providerID
        return result
    }
}

@MainActor
private final class FakeInsertionReadiness: DictationInsertionReadiness {
    var result = true
    private(set) var callCount = 0
    private let events: EventRecorder

    init(events: EventRecorder) {
        self.events = events
    }

    func waitUntilReady() async -> Bool {
        callCount += 1
        events.record("readiness")
        return result
    }
}

@MainActor
private final class FakeTextInserter: DictationTextInserting {
    var outcome: TextInsertionOutcome = .inserted
    private(set) var callCount = 0
    private let events: EventRecorder

    init(events: EventRecorder) {
        self.events = events
    }

    func insert(_ text: String) async -> TextInsertionOutcome {
        callCount += 1
        events.record("insert")
        return outcome
    }
}

@MainActor
private final class FakeSettingsWindowPresenter: SettingsWindowPresenting {
    private(set) var showCount = 0

    func show() {
        showCount += 1
    }
}

@MainActor
private final class FakeHistoryPurger: DictationHistoryPurging {
    private(set) var purgeCount = 0

    @discardableResult
    func purgeExpired() -> Bool {
        purgeCount += 1
        return true
    }
}

@MainActor
private func testDeliverSavesHistoryBeforeReadinessAndInsertion() async throws {
    let events = EventRecorder()
    let history = FakeHistoryRecorder(events: events)
    let readiness = FakeInsertionReadiness(events: events)
    let inserter = FakeTextInserter(events: events)
    inserter.outcome = .copied("fallback")
    let coordinator = DictationOutputCoordinator(
        history: history,
        readiness: readiness,
        inserter: inserter
    )

    let outcome = await coordinator.deliver(
        text: "final text",
        providerID: "fun-asr"
    )

    try expect(
        events.values,
        equals: ["history", "readiness", "insert"],
        "output delivery order"
    )
    try expect(history.receivedText, equals: "final text", "history text")
    try expect(
        history.receivedProviderID,
        equals: "fun-asr",
        "history provider"
    )
    try expect(readiness.callCount, equals: 1, "readiness call count")
    try expect(inserter.callCount, equals: 1, "insertion call count")
    try expect(outcome, equals: .copied("fallback"), "insertion outcome")
}

@MainActor
private func testHistorySaveFailureStillReachesInsertion() async throws {
    let events = EventRecorder()
    let history = FakeHistoryRecorder(events: events)
    history.result = false
    let readiness = FakeInsertionReadiness(events: events)
    let inserter = FakeTextInserter(events: events)
    let coordinator = DictationOutputCoordinator(
        history: history,
        readiness: readiness,
        inserter: inserter
    )

    let outcome = await coordinator.deliver(
        text: "keep going",
        providerID: "mimo"
    )

    try expect(
        events.values,
        equals: ["history", "readiness", "insert"],
        "failed history save delivery order"
    )
    try expect(inserter.callCount, equals: 1, "failed save insertion count")
    try expect(outcome, equals: .inserted, "failed save insertion outcome")
}

@MainActor
private func testRejectedReadinessPreventsInsertion() async throws {
    let events = EventRecorder()
    let history = FakeHistoryRecorder(events: events)
    let readiness = FakeInsertionReadiness(events: events)
    readiness.result = false
    let inserter = FakeTextInserter(events: events)
    let coordinator = DictationOutputCoordinator(
        history: history,
        readiness: readiness,
        inserter: inserter
    )

    let outcome = await coordinator.deliver(
        text: "saved anyway",
        providerID: "fun-asr"
    )

    try expect(
        events.values,
        equals: ["history", "readiness"],
        "rejected readiness delivery order"
    )
    try expect(readiness.callCount, equals: 1, "rejected readiness call count")
    try expect(inserter.callCount, equals: 0, "rejected insertion count")
    try expect(outcome, equals: nil, "rejected insertion outcome")
}

@MainActor
private func testSettingsNavigationStartsAtStartPane() throws {
    let state = SettingsNavigationState()

    try expect(state.selection, equals: .start, "initial settings pane")
}

@MainActor
private func testOpenHistorySelectsHistoryAndShowsWindow() throws {
    let state = SettingsNavigationState()
    let presenter = FakeSettingsWindowPresenter()
    let purger = FakeHistoryPurger()
    let coordinator = SettingsNavigationCoordinator(
        state: state,
        historyPurger: purger
    )
    coordinator.attach(presenter)

    coordinator.openHistory()

    try expect(state.selection, equals: .history, "history settings pane")
    try expect(presenter.showCount, equals: 1, "history window show count")
    try expect(purger.purgeCount, equals: 1, "history open purge count")
}

@MainActor
private func testOpenSettingsPreservesCurrentSelection() throws {
    let state = SettingsNavigationState()
    let presenter = FakeSettingsWindowPresenter()
    let coordinator = SettingsNavigationCoordinator(state: state)
    coordinator.attach(presenter)
    coordinator.openHistory()

    coordinator.openSettings()

    try expect(
        state.selection,
        equals: .history,
        "ordinary settings preserves current pane"
    )
    try expect(presenter.showCount, equals: 2, "settings window show count")
}

private func testAudioConfigurationChangeRestartsCapture() throws {
    var lifecycle = AudioCaptureLifecycleStateMachine(
        maximumRestartAttempts: 2,
        restartDelayMilliseconds: 180
    )

    try expect(
        lifecycle.handle(.startRequested),
        equals: [.startEngine],
        "capture start action"
    )
    try expect(
        lifecycle.handle(.engineStarted),
        equals: [],
        "capture start completion"
    )
    try expect(
        lifecycle.handle(.configurationChanged),
        equals: [
            .releaseEngine,
            .scheduleRestart(afterMilliseconds: 180)
        ],
        "Bluetooth route change recovery"
    )
    try expect(
        lifecycle.handle(.restartSucceeded),
        equals: [],
        "capture restart completion"
    )
}

private func testAudioStopCancelsRecoveryAndReleasesEngine() throws {
    var lifecycle = AudioCaptureLifecycleStateMachine()

    _ = lifecycle.handle(.startRequested)
    _ = lifecycle.handle(.engineStarted)
    _ = lifecycle.handle(.configurationChanged)

    try expect(
        lifecycle.handle(.stopRequested),
        equals: [.cancelScheduledRestart, .releaseEngine],
        "capture stop during route recovery"
    )
    try expect(
        lifecycle.handle(.restartSucceeded),
        equals: [],
        "stale restart ignored after stop"
    )
}

private func testAudioRecoveryReportsOnlyAfterRetriesExhausted() throws {
    var lifecycle = AudioCaptureLifecycleStateMachine(
        maximumRestartAttempts: 2,
        restartDelayMilliseconds: 50
    )

    _ = lifecycle.handle(.startRequested)
    _ = lifecycle.handle(.engineStarted)
    _ = lifecycle.handle(.configurationChanged)

    try expect(
        lifecycle.handle(.restartFailed),
        equals: [
            .releaseEngine,
            .scheduleRestart(afterMilliseconds: 50)
        ],
        "first restart failure retries"
    )
    try expect(
        lifecycle.handle(.restartFailed),
        equals: [.releaseEngine, .reportFailure],
        "final restart failure reports"
    )
}

private func testBluetoothHeadsetRecordsFromBuiltInMicrophone() throws {
    try expect(
        AudioInputRoute.preferredDeviceUID(
            defaultInput: .classicBluetooth,
            builtInMicrophoneUID: "BuiltInMicrophoneDevice"
        ),
        equals: "BuiltInMicrophoneDevice",
        "Bluetooth headset input records the Mac's own microphone"
    )
    try expect(
        AudioInputRoute.preferredDeviceUID(
            defaultInput: .classicBluetooth,
            builtInMicrophoneUID: nil
        ),
        equals: nil,
        "headset input without a built-in microphone keeps the system default"
    )
    try expect(
        AudioInputRoute.preferredDeviceUID(
            defaultInput: .builtInOrWired,
            builtInMicrophoneUID: "BuiltInMicrophoneDevice"
        ),
        equals: nil,
        "built-in and wired inputs keep the system default"
    )
}

/// Opt-in hardware check: reports the live input route and asserts the policy holds.
@MainActor
private func testLiveCaptureRoute() throws {
    let transport = AudioInputRoute.defaultInputTransportKind()
    let builtIn = AudioInputRoute.builtInMicrophoneUID()
    let resolved = AudioInputRoute.captureDeviceUID()
    try expect(
        resolved,
        equals: AudioInputRoute.preferredDeviceUID(
            defaultInput: transport,
            builtInMicrophoneUID: builtIn
        ),
        "live route follows the policy"
    )
    if transport == .classicBluetooth {
        try expect(resolved, equals: builtIn, "headset input records the built-in microphone")
        try expect(resolved?.isEmpty == false, equals: true, "built-in microphone exists")
    } else {
        try expect(resolved, equals: nil, "no headset input means no device override")
    }
    print(
        "PASS live capture route: transport=\(transport) builtIn=\(builtIn ?? "none") resolved=\(resolved ?? "system default")"
    )
}

@MainActor
private final class FakeOutputMuteHardware {
    let domain = "ziki.tests.outputmute.\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: domain)!
    var current: String? = "speaker"
    var muted = ["speaker": false, "headphones": false]
    var events: [String] = []
    var failedWrites = Set<String>()
    lazy var controller = makeController()

    func makeController() -> RecordingOutputMute {
        RecordingOutputMute(defaults: defaults, currentDevice: { [unowned self] in current },
            readMute: { [unowned self] in muted[$0] },
            writeMute: { [unowned self] uid, value in
                events.append("\(uid)=\(value)")
                guard !failedWrites.contains(uid) else { return false }
                muted[uid] = value
                return true
            })
    }

    func clean() { defaults.removePersistentDomain(forName: domain) }
}

@MainActor
private func testRecordingMuteOrderingAndFailureCleanup() throws {
    let hardware = FakeOutputMuteHardware()
    defer { hardware.clean() }
    let mute = hardware.controller
    try mute.start(enabled: true) { hardware.events.append("start microphone") }
    let result = mute.stop { hardware.events.append("stop microphone"); return "PCM" }
    try expect(result, equals: "PCM", "stop preserves captured audio")
    try expect(hardware.events, equals: ["speaker=true", "start microphone", "stop microphone", "speaker=false"], "mute surrounds actual capture only")
    mute.stop {}
    try expect(hardware.events.count, equals: 4, "repeated cancel/stop does not restore twice")
    do {
        try mute.start(enabled: true) { throw TestFailure(description: "engine failed") }
        throw TestFailure(description: "start error was swallowed")
    } catch let error as TestFailure {
        try expect(error.description, equals: "engine failed", "start failure propagated")
    }
    try expect(hardware.muted["speaker"], equals: false, "start failure restores sound")
    try expect(mute.hasPendingRecovery, equals: false, "successful cleanup clears journal")
}

@MainActor
private func testRecordingMutePreservesUserStateAndDisabledMode() throws {
    let hardware = FakeOutputMuteHardware()
    defer { hardware.clean() }
    let mute = hardware.controller
    hardware.muted["speaker"] = true
    try mute.start(enabled: true) {}
    mute.stop {}
    try expect(hardware.events, equals: [], "already muted remains muted")
    hardware.muted["speaker"] = false
    try mute.start(enabled: false) {}
    hardware.current = "headphones"
    mute.outputDeviceChanged()
    mute.stop {}
    try expect(hardware.events, equals: [], "disabled mode never touches hardware")
    try mute.start(enabled: true) {}
    hardware.muted["headphones"] = false // User explicitly unmutes while recording.
    mute.outputDeviceChanged()
    mute.stop {}
    try expect(hardware.events, equals: ["headphones=true"], "manual unmute not undone or forced back")
    mute.outputDeviceChanged()
    try expect(hardware.events.count, equals: 1, "late route callbacks do nothing after stop")
}

@MainActor
private func testRecordingMuteRouteChangeAndRecoveryJournal() throws {
    let hardware = FakeOutputMuteHardware()
    defer { hardware.clean() }
    let mute = hardware.controller
    try mute.start(enabled: true) {}
    hardware.current = "headphones"
    mute.outputDeviceChanged()
    try expect(hardware.events, equals: ["speaker=true", "headphones=true", "speaker=false"], "new route muted before old restored")
    hardware.failedWrites.insert("headphones")
    mute.stop {}
    try expect(mute.hasPendingRecovery, equals: true, "restore failure remains recoverable")
    let restarted = hardware.makeController()
    try expect(restarted.hasPendingRecovery, equals: true, "journal survives process recreation")
    try expect(hardware.muted["headphones"], equals: true, "restart never silently unmutes")
    hardware.muted.removeValue(forKey: "headphones")
    restarted.recoverPending()
    try expect(restarted.hasPendingRecovery, equals: true, "unplugged UID retained")
    hardware.failedWrites.removeAll()
    hardware.muted["headphones"] = true
    restarted.recoverPending()
    try expect(hardware.muted["headphones"], equals: false, "reconnected device restored by stable UID")
    try expect(restarted.hasPendingRecovery, equals: false, "explicit recovery clears journal")
}

@MainActor
private func testRecordingMuteUnsupportedAndWriteFailure() throws {
    let hardware = FakeOutputMuteHardware()
    defer { hardware.clean() }
    let mute = hardware.controller
    hardware.current = "unsupported"
    var captured = false
    try mute.start(enabled: true) { captured = true }
    mute.stop {}
    try expect(captured, equals: true, "unsupported mute never blocks dictation")
    try expect(mute.notice != nil, equals: true, "unsupported device is explained")
    hardware.current = "speaker"
    hardware.failedWrites.insert("speaker")
    try mute.start(enabled: true) {}
    mute.stop {}
    try expect(hardware.muted["speaker"], equals: false, "failed mute does not change original state")
    try expect(mute.hasPendingRecovery, equals: false, "unchanged hardware has no stale recovery")
}

/// Opt-in smoke test: briefly changes only current output mute, never records audio.
@MainActor
private func testLiveOutputMute() throws {
    func read(_ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0
        var size: UInt32 = 4
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
            0, nil, &size, &device) == noErr else { throw TestFailure(description: "no output device") }
        address.mSelector = selector
        address.mScope = kAudioDevicePropertyScopeOutput
        var value: UInt32 = 0
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            throw TestFailure(description: "output property unavailable")
        }
        return value
    }
    let beforeMute = try read(kAudioDevicePropertyMute)
    let beforeVolume = try read(kAudioDevicePropertyVolumeScalar)
    let mute = RecordingOutputMute()
    defer { mute.stop {} }
    try mute.start(enabled: true) {
        try expect(read(kAudioDevicePropertyMute), equals: 1, "muted before microphone would start")
        try expect(read(kAudioDevicePropertyVolumeScalar), equals: beforeVolume, "volume unchanged while muted")
    }
    mute.stop {}
    try expect(read(kAudioDevicePropertyMute), equals: beforeMute, "original mute restored")
    try expect(read(kAudioDevicePropertyVolumeScalar), equals: beforeVolume, "original volume preserved")
    print("PASS live output mute and restore; volume unchanged")
}

@main
private enum ZikiAppTestHarness {
    static func main() async {
        if CommandLine.arguments.contains("--live-output-mute") {
            do { try testLiveOutputMute() } catch { print("FAIL live output mute: \(error)"); exit(1) }
            return
        }

        if CommandLine.arguments.contains("--live-capture-route") {
            do { try testLiveCaptureRoute() } catch { print("FAIL live capture route: \(error)"); exit(1) }
            return
        }
        let tests: [(String, @MainActor () async throws -> Void)] = [
            ("Recording mute ordering and failure cleanup", testRecordingMuteOrderingAndFailureCleanup),
            ("Recording mute preserves user state and disabled mode", testRecordingMutePreservesUserStateAndDisabledMode),
            ("Recording mute route change and recovery journal", testRecordingMuteRouteChangeAndRecoveryJournal),
            ("Recording mute unsupported and write failure", testRecordingMuteUnsupportedAndWriteFailure),
            (
                "Delivery saves history before readiness and insertion",
                testDeliverSavesHistoryBeforeReadinessAndInsertion
            ),
            (
                "History save failure still reaches insertion",
                testHistorySaveFailureStillReachesInsertion
            ),
            (
                "Rejected readiness prevents insertion",
                testRejectedReadinessPreventsInsertion
            ),
            (
                "Settings navigation starts at Start pane",
                testSettingsNavigationStartsAtStartPane
            ),
            (
                "Open History selects History and shows window",
                testOpenHistorySelectsHistoryAndShowsWindow
            ),
            (
                "Open Settings preserves current selection",
                testOpenSettingsPreservesCurrentSelection
            ),
            (
                "Audio configuration change restarts capture",
                testAudioConfigurationChangeRestartsCapture
            ),
            (
                "Audio stop cancels recovery and releases engine",
                testAudioStopCancelsRecoveryAndReleasesEngine
            ),
            (
                "Audio recovery reports only after retries exhaust",
                testAudioRecoveryReportsOnlyAfterRetriesExhausted
            ),
            (
                "Bluetooth headset records from the built-in microphone",
                testBluetoothHeadsetRecordsFromBuiltInMicrophone
            )
        ]
        var failures = 0

        for (name, test) in tests {
            do {
                try await test()
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }

        print("\(tests.count - failures)/\(tests.count) tests passed")
        if failures > 0 {
            exit(1)
        }
    }
}
