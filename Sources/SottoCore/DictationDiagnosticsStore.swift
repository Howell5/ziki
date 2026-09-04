import Foundation

public struct DictationDiagnosticEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let stage: String
    public let detail: String?
}

public struct DictationDiagnosticDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sessionID: UUID
    public let startedAt: Date
    public var updatedAt: Date
    public let providerID: String
    public let regionID: String
    public let sampleRate: Int
    public let cleanupEnabled: Bool
    public var capturedAudioBytes: Int? = nil
    public var capturedAudioDurationSeconds: Double? = nil
    public var asrTextAtStop: String? = nil
    public var asrLatestText: String? = nil
    public var asrFinalText: String? = nil
    public var qwenCandidateText: String? = nil
    public var cleanupDecision: String? = nil
    public var finalText: String? = nil
    public var outcome: String? = nil
    public var errorStage: String? = nil
    public var errorMessage: String? = nil
    public var events: [DictationDiagnosticEvent]
}

public final class DictationDiagnosticsStore {
    public static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    public let directoryURL: URL

    private let now: () -> Date
    private let fileManager: FileManager
    private var documents: [UUID: DictationDiagnosticDocument] = [:]

    public convenience init() {
        self.init(directoryURL: Self.defaultDirectoryURL())
    }

    public init(
        directoryURL: URL,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.now = now
        self.fileManager = fileManager
        purgeExpired(referenceDate: now())
    }

    public func begin(
        sessionID: UUID,
        providerID: String,
        regionID: String,
        sampleRate: Int,
        cleanupEnabled: Bool
    ) {
        let timestamp = now()
        documents[sessionID] = DictationDiagnosticDocument(
            schemaVersion: 1,
            sessionID: sessionID,
            startedAt: timestamp,
            updatedAt: timestamp,
            providerID: providerID,
            regionID: regionID,
            sampleRate: sampleRate,
            cleanupEnabled: cleanupEnabled,
            events: [
                .init(
                    timestamp: timestamp,
                    stage: "session_started",
                    detail: nil
                )
            ]
        )
        purgeExpired(referenceDate: timestamp)
        persist(sessionID)
    }

    public func recordStage(
        sessionID: UUID,
        stage: String,
        detail: String? = nil
    ) {
        update(sessionID, stage: stage, detail: detail) { _ in }
    }

    public func recordAudio(
        sessionID: UUID,
        pcm16: Data,
        sampleRate: Int,
        asrTextAtStop: String
    ) {
        guard documents[sessionID] != nil else { return }
        do {
            try prepareSessionDirectory(sessionID)
            let wav = try PCM16WAVEncoder().encode(
                pcm16,
                sampleRate: sampleRate,
                channelCount: 1
            )
            let audioURL = sessionDirectoryURL(sessionID)
                .appendingPathComponent("audio.wav")
            try wav.write(to: audioURL, options: .atomic)
            try protect(audioURL, permissions: 0o600)
        } catch {
            update(
                sessionID,
                stage: "diagnostics_write_failed",
                detail: error.localizedDescription
            ) { document in
                document.errorStage = "diagnostics"
                document.errorMessage = error.localizedDescription
            }
            return
        }

        update(
            sessionID,
            stage: "recording_stopped",
            detail: "\(pcm16.count) PCM bytes"
        ) { document in
            document.capturedAudioBytes = pcm16.count
            document.capturedAudioDurationSeconds =
                Double(pcm16.count) / Double(max(1, sampleRate * 2))
            document.asrTextAtStop = asrTextAtStop
        }
    }

    public func recordASRProgress(sessionID: UUID, text: String) {
        update(sessionID, stage: "asr_segment_final") { document in
            document.asrLatestText = text
        }
    }

    public func recordASRCompletion(
        sessionID: UUID,
        text: String,
        billedSeconds: Double?
    ) {
        update(
            sessionID,
            stage: "asr_completed",
            detail: billedSeconds.map { "\($0) billed seconds" }
        ) { document in
            document.asrLatestText = text
            document.asrFinalText = text
        }
    }

    public func recordCleanup(
        sessionID: UUID,
        candidate: String?,
        decision: String,
        finalText: String
    ) {
        update(sessionID, stage: "cleanup_completed", detail: decision) {
            document in
            document.qwenCandidateText = candidate
            document.cleanupDecision = decision
            document.finalText = finalText
        }
    }

    public func recordFailure(
        sessionID: UUID,
        stage: String,
        message: String,
        partialText: String? = nil
    ) {
        update(sessionID, stage: "failed", detail: stage) { document in
            document.errorStage = stage
            document.errorMessage = message
            if let partialText {
                document.qwenCandidateText = partialText
            }
            document.outcome = "failed"
        }
    }

    public func recordOutcome(
        sessionID: UUID,
        outcome: String,
        detail: String? = nil
    ) {
        update(sessionID, stage: "session_finished", detail: detail) {
            document in
            document.outcome = outcome
        }
    }

    public func removeAll() {
        documents.removeAll()
        try? fileManager.removeItem(at: directoryURL)
    }

    @discardableResult
    public func prepareDirectoryForViewing() -> Bool {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try excludeFromBackup(directoryURL)
            return true
        } catch {
            return false
        }
    }

    private func update(
        _ sessionID: UUID,
        stage: String,
        detail: String? = nil,
        mutation: (inout DictationDiagnosticDocument) -> Void
    ) {
        guard var document = documents[sessionID] else { return }
        mutation(&document)
        let timestamp = now()
        document.updatedAt = timestamp
        document.events.append(
            .init(timestamp: timestamp, stage: stage, detail: detail)
        )
        documents[sessionID] = document
        persist(sessionID)
    }

    private func persist(_ sessionID: UUID) {
        guard let document = documents[sessionID] else { return }
        do {
            try prepareSessionDirectory(sessionID)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let fileURL = sessionDirectoryURL(sessionID)
                .appendingPathComponent("session.json")
            try encoder.encode(document).write(to: fileURL, options: .atomic)
            try protect(fileURL, permissions: 0o600)
        } catch {
            // Diagnostics are best-effort and must never interrupt dictation.
        }
    }

    private func purgeExpired(referenceDate: Date) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let cutoff = referenceDate.addingTimeInterval(-Self.retentionInterval)
        for entry in entries {
            let modifiedAt = try? entry.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            if let modifiedAt, modifiedAt < cutoff {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    private func prepareSessionDirectory(_ sessionID: UUID) throws {
        try fileManager.createDirectory(
            at: sessionDirectoryURL(sessionID),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try excludeFromBackup(directoryURL)
    }

    private func sessionDirectoryURL(_ sessionID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            sessionID.uuidString.lowercased(),
            isDirectory: true
        )
    }

    private func protect(_ url: URL, permissions: Int) throws {
        try fileManager.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
        try excludeFromBackup(url)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }

    private static func defaultDirectoryURL() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Sotto", isDirectory: true)
        .appendingPathComponent("Diagnostics", isDirectory: true)
    }
}
