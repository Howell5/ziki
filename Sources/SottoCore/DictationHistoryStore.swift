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
    public typealias Reader = (URL) throws -> Data
    public typealias Mover = (URL, URL) throws -> Void

    @Published public private(set) var entries: [DictationHistoryEntry] = []
    @Published public private(set) var errorMessage: String?

    public let fileURL: URL

    private let now: Clock
    private let writeData: Writer
    private let readData: Reader
    private let moveItem: Mover
    private let scheduler: any DictationHistoryExpirationScheduling
    private let fileManager: FileManager
    private var hasLoadedPersistentState = false

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
        readData: Reader? = nil,
        moveItem: Mover? = nil,
        scheduler: any DictationHistoryExpirationScheduling,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.now = now
        self.fileManager = fileManager
        self.writeData = writeData ?? Self.atomicWrite
        self.readData = readData ?? Self.readFile
        self.moveItem = moveItem ?? fileManager.moveItem
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
        guard ensureLoaded() else {
            entries.append(
                DictationHistoryEntry(
                    id: UUID(),
                    text: text,
                    createdAt: now(),
                    providerID: providerID
                )
            )
            entries = DictationHistoryPolicy.sortedNewestFirst(entries)
            scheduleLoadRetry()
            return false
        }

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
        guard ensureLoaded() else {
            scheduleLoadRetry()
            return false
        }
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
        guard ensureLoaded() else {
            scheduleLoadRetry()
            return false
        }
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
        guard ensureLoaded() else {
            scheduleLoadRetry()
            return false
        }
        return purgeExpiredLoadedState()
    }

    private func purgeExpiredLoadedState() -> Bool {
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
        let pendingEntries = entries
        do {
            try prepareDirectory()
            guard fileManager.fileExists(atPath: fileURL.path) else {
                hasLoadedPersistentState = true
                if !pendingEntries.isEmpty, !persist() {
                    scheduleLoadRetry()
                    return
                }
                scheduleNextExpiration()
                return
            }

            let data: Data
            do {
                data = try readData(fileURL)
            } catch {
                hasLoadedPersistentState = false
                errorMessage = "历史记录暂时无法读取；原文件不会被覆盖。"
                scheduleLoadRetry()
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document: DictationHistoryDocument
            do {
                document = try decoder.decode(
                    DictationHistoryDocument.self,
                    from: data
                )
                guard document.schemaVersion
                    == DictationHistoryPolicy.schemaVersion
                else {
                    throw DictationHistoryStoreError.unsupportedSchema
                }
            } catch {
                guard quarantineCorruptFile() else {
                    hasLoadedPersistentState = false
                    errorMessage = "历史记录文件已损坏，但无法保留备份；原文件不会被覆盖。"
                    scheduleLoadRetry()
                    return
                }
                hasLoadedPersistentState = true
                entries = DictationHistoryPolicy.sortedNewestFirst(
                    pendingEntries
                )
                errorMessage = "历史记录文件无法读取，已保留损坏备份。"
                if !pendingEntries.isEmpty {
                    _ = persist()
                }
                scheduleNextExpiration()
                return
            }

            hasLoadedPersistentState = true
            entries = DictationHistoryPolicy.sortedNewestFirst(
                document.entries + pendingEntries
            )
            let retained = DictationHistoryPolicy.sortedNewestFirst(
                DictationHistoryPolicy.retained(entries, now: now())
            )
            let needsPersistence =
                retained != entries || !pendingEntries.isEmpty
            entries = retained
            if needsPersistence {
                _ = persist()
            } else {
                errorMessage = nil
            }
            scheduleNextExpiration()
        } catch {
            hasLoadedPersistentState = false
            errorMessage = "历史记录存储暂时不可用；原文件不会被覆盖。"
            scheduleLoadRetry()
        }
    }

    private func persist() -> Bool {
        guard hasLoadedPersistentState else {
            errorMessage = "历史记录尚未安全载入；原文件不会被覆盖。"
            return false
        }
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
        guard ensureLoaded() else {
            scheduleLoadRetry()
            return
        }
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
        guard hasLoadedPersistentState else {
            retryLoad()
            return
        }
        guard persist() else {
            scheduleExpirationRetry()
            return
        }
        scheduleNextExpiration()
    }

    private func ensureLoaded() -> Bool {
        guard !hasLoadedPersistentState else { return true }
        load()
        return hasLoadedPersistentState
    }

    private func scheduleLoadRetry() {
        scheduler.cancel()
        scheduler.schedule(at: now().addingTimeInterval(5 * 60)) {
            [weak self] in
            self?.retryLoad()
        }
    }

    private func retryLoad() {
        guard ensureLoaded() else {
            scheduleLoadRetry()
            return
        }
        _ = purgeExpiredLoadedState()
    }

    private func prepareDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try excludeFromBackup(directory)
    }

    private func quarantineCorruptFile() -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else { return true }
        let timestamp = Int(now().timeIntervalSince1970)
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "dictation-history.corrupt-\(timestamp).json"
            )
        do {
            try moveItem(fileURL, backupURL)
        } catch {
            return false
        }
        try? excludeFromBackup(backupURL)
        return true
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

    private static func readFile(from url: URL) throws -> Data {
        try Data(contentsOf: url)
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
