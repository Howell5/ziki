import Foundation

public struct DictationContext: Sendable {
    public struct Turn: Codable, Equatable, Sendable {
        public let rawTranscript: String
        public let polishedTranscript: String

        public init(rawTranscript: String, polishedTranscript: String) {
            self.rawTranscript = rawTranscript
            self.polishedTranscript = polishedTranscript
        }
    }

    public private(set) var turns: [Turn] = []
    private var applicationID: String?
    private var lastUpdated: Date?

    public init() {}

    public mutating func prepare(applicationID: String?, now: Date = Date()) {
        // ponytail: app + 10-minute gap is only a conversation heuristic;
        // explicit reset handles separate chats in the same app until real chat IDs exist.
        if applicationID == nil || applicationID != self.applicationID
            || lastUpdated.map({ now.timeIntervalSince($0) >= 600 || now < $0 }) == true {
            clear()
        }
        self.applicationID = applicationID
    }

    public mutating func append(raw: String, polished: String, now: Date = Date()) {
        guard applicationID != nil else { return }
        let turn = Turn(rawTranscript: raw, polishedTranscript: polished)
        // Keep complete turns, never clipped fragments. Long dictations still receive
        // full cleanup; only their reuse as context is bounded.
        guard raw.count + polished.count <= 8_000 else {
            turns.removeAll()
            lastUpdated = nil
            return
        }
        turns.append(turn)
        while turns.count > 3
            || turns.reduce(0, { $0 + $1.rawTranscript.count + $1.polishedTranscript.count }) > 8_000 {
            turns.removeFirst()
        }
        lastUpdated = now
    }

    public mutating func clear() {
        turns.removeAll()
        applicationID = nil
        lastUpdated = nil
    }
}
