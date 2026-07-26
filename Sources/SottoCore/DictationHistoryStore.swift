import Combine
import Foundation

@MainActor
public protocol DictationHistoryExpirationScheduling: AnyObject {
    func schedule(
        at date: Date,
        action: @escaping @MainActor () -> Void
    )
    func cancel()
}

@MainActor
public final class DictationHistoryTaskScheduler:
    DictationHistoryExpirationScheduling
{
    private var task: Task<Void, Never>?

    public init() {}

    public func schedule(
        at date: Date,
        action: @escaping @MainActor () -> Void
    ) {
        cancel()
        let delay = max(0, date.timeIntervalSinceNow)
        task = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
public final class DictationHistoryStore: ObservableObject {
    public typealias Clock = () -> Date
    public typealias Writer = (Data, URL) throws -> Void

    @Published public private(set) var entries: [DictationHistoryEntry] = []
    @Published public private(set) var errorMessage: String?

    public let fileURL: URL

    private let now: Clock
    private let writeData: Writer
    private let scheduler: any DictationHistoryExpirationScheduling
    private let fileManager: FileManager

    public convenience init() {
        self.init(
            fileURL: Self.defaultFileURL(),
            scheduler: DictationHistoryTaskScheduler()
        )
    }

    public init(
        fileURL: URL,
        now: @escaping Clock = Date.init,
        writeData: Writer? = nil,
        scheduler: any DictationHistoryExpirationScheduling,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.now = now
        self.fileManager = fileManager
        self.writeData = writeData ?? Self.atomicWrite
        self.scheduler = scheduler
        load()
    }

    deinit {
        MainActor.assumeIsolated {
            scheduler.cancel()
        }
    }

    @discardableResult
    public func append(text: String, providerID: String) -> Bool {
        let normalizedText = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedText.isEmpty else { return true }

        _ = purgeExpired()
        entries.append(
            DictationHistoryEntry(
                id: UUID(),
                text: text,
                createdAt: now(),
                providerID: providerID
            )
        )
        entries = DictationHistoryPolicy.sortedNewestFirst(entries)

        let saved = persist()
        scheduleNextExpiration()
        return saved
    }

    @discardableResult
    public func delete(id: UUID) -> Bool {
        let previousEntries = entries
        entries.removeAll { $0.id == id }
        guard entries != previousEntries else { return true }

        guard persist() else {
            entries = previousEntries
            scheduleNextExpiration()
            return false
        }
        scheduleNextExpiration()
        return true
    }

    @discardableResult
    public func clearAll() -> Bool {
        guard !entries.isEmpty else { return true }
        let previousEntries = entries
        entries = []

        guard persist() else {
            entries = previousEntries
            scheduleNextExpiration()
            return false
        }
        scheduleNextExpiration()
        return true
    }

    @discardableResult
    public func purgeExpired() -> Bool {
        let retained = DictationHistoryPolicy.sortedNewestFirst(
            DictationHistoryPolicy.retained(entries, now: now())
        )
        guard retained != entries else {
            scheduleNextExpiration()
            return true
        }

        entries = retained
        guard persist() else {
            scheduleExpirationRetry()
            return false
        }
        scheduleNextExpiration()
        return true
    }

    public func search(_ query: String) -> [DictationHistoryEntry] {
        DictationHistoryPolicy.matching(entries, query: query)
    }

    private func load() {
        do {
            try prepareDirectory()
            guard fileManager.fileExists(atPath: fileURL.path) else {
                scheduleNextExpiration()
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(
                DictationHistoryDocument.self,
                from: Data(contentsOf: fileURL)
            )
            guard document.schemaVersion == DictationHistoryPolicy.schemaVersion
            else {
                throw DictationHistoryStoreError.unsupportedSchema
            }
            entries = DictationHistoryPolicy.sortedNewestFirst(document.entries)
            _ = purgeExpired()
        } catch {
            backUpCorruptFileIfPresent()
            entries = []
            errorMessage = "历史记录文件无法读取，已保留损坏备份。"
            scheduleNextExpiration()
        }
    }

    private func persist() -> Bool {
        do {
            try prepareDirectory()
            let document = DictationHistoryDocument(
                schemaVersion: DictationHistoryPolicy.schemaVersion,
                entries: DictationHistoryPolicy.sortedNewestFirst(entries)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try writeData(encoder.encode(document), fileURL)
            try excludeFromBackup(fileURL)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "历史记录暂时无法保存，稍后会再次尝试。"
            return false
        }
    }

    private func scheduleNextExpiration() {
        scheduler.cancel()
        guard let date = DictationHistoryPolicy.nextExpirationDate(
            for: entries
        ) else {
            return
        }
        scheduler.schedule(at: date) { [weak self] in
            self?.expireScheduledEntries()
        }
    }

    private func expireScheduledEntries() {
        let retained = DictationHistoryPolicy.sortedNewestFirst(
            DictationHistoryPolicy.retained(entries, now: now())
        )
        entries = retained
        guard persist() else {
            scheduleExpirationRetry()
            return
        }
        scheduleNextExpiration()
    }

    private func scheduleExpirationRetry() {
        scheduler.cancel()
        scheduler.schedule(at: now().addingTimeInterval(5 * 60)) {
            [weak self] in
            self?.retryExpirationPersistence()
        }
    }

    private func retryExpirationPersistence() {
        guard persist() else {
            scheduleExpirationRetry()
            return
        }
        scheduleNextExpiration()
    }

    private func prepareDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try excludeFromBackup(directory)
    }

    private func backUpCorruptFileIfPresent() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let timestamp = Int(now().timeIntervalSince1970)
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "dictation-history.corrupt-\(timestamp).json"
            )
        try? fileManager.moveItem(at: fileURL, to: backupURL)
        try? excludeFromBackup(backupURL)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupport
            .appendingPathComponent("Sotto", isDirectory: true)
            .appendingPathComponent("dictation-history.json")
    }
}

private enum DictationHistoryStoreError: Error {
    case unsupportedSchema
}
