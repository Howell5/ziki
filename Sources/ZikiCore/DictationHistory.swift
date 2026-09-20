import Foundation

public struct DictationHistoryEntry:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public let text: String
    public let createdAt: Date
    public let providerID: String

    public init(
        id: UUID,
        text: String,
        createdAt: Date,
        providerID: String
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.providerID = providerID
    }
}

public struct DictationHistoryDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var entries: [DictationHistoryEntry]

    public init(schemaVersion: Int, entries: [DictationHistoryEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}

public enum DictationHistoryPolicy {
    public static let schemaVersion = 1
    public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    public static func retained(
        _ entries: [DictationHistoryEntry],
        now: Date
    ) -> [DictationHistoryEntry] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        return entries.filter { $0.createdAt > cutoff }
    }

    public static func sortedNewestFirst(
        _ entries: [DictationHistoryEntry]
    ) -> [DictationHistoryEntry] {
        entries.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString > $1.id.uuidString
            }
            return $0.createdAt > $1.createdAt
        }
    }

    public static func matching(
        _ entries: [DictationHistoryEntry],
        query: String
    ) -> [DictationHistoryEntry] {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedQuery.isEmpty else { return entries }
        return entries.filter {
            $0.text.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    public static func nextExpirationDate(
        for entries: [DictationHistoryEntry]
    ) -> Date? {
        entries.map(\.createdAt).min()?.addingTimeInterval(retentionInterval)
    }

    public static func providerTitle(for providerID: String) -> String {
        switch providerID {
        case "fun-asr":
            "Bailian Realtime ASR"
        case "mimo":
            "MiMo-V2.5-ASR"
        default:
            "未知语音服务"
        }
    }
}
