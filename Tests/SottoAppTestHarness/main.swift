import Darwin
import Foundation
import SottoAppCore

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

@main
private enum SottoAppTestHarness {
    static func main() async {
        let tests: [(String, @MainActor () async throws -> Void)] = [
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
