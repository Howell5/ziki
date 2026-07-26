import SottoCore

public enum TextInsertionOutcome: Equatable, Sendable {
    case inserted
    case copied(String)
}

@MainActor
public protocol DictationHistoryRecording: AnyObject {
    @discardableResult
    func append(text: String, providerID: String) -> Bool
}

@MainActor
public protocol DictationInsertionReadiness: AnyObject {
    func waitUntilReady() async -> Bool
}

@MainActor
public protocol DictationTextInserting: AnyObject {
    func insert(_ text: String) async -> TextInsertionOutcome
}

extension DictationHistoryStore: DictationHistoryRecording {}

@MainActor
public final class DictationOutputCoordinator {
    private let history: any DictationHistoryRecording
    private let readiness: any DictationInsertionReadiness
    private let inserter: any DictationTextInserting

    public init(
        history: any DictationHistoryRecording,
        readiness: any DictationInsertionReadiness,
        inserter: any DictationTextInserting
    ) {
        self.history = history
        self.readiness = readiness
        self.inserter = inserter
    }

    public func deliver(
        text: String,
        providerID: String
    ) async -> TextInsertionOutcome? {
        history.append(text: text, providerID: providerID)
        guard await readiness.waitUntilReady() else { return nil }
        return await inserter.insert(text)
    }
}
