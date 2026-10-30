import Foundation
import Dispatch

/// Persistence boundary for emoji usage history.
///
/// Keeping storage behind this small interface makes the history logic testable without touching
/// a user's Application Support directory.
public protocol UsageHistoryStorage: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

/// JSON-file backing storage used by the app.
public struct JSONFileUsageHistoryStorage: UsageHistoryStorage, @unchecked Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Thread-safe frecency store: use counts and last-use times, persisted as JSON.
public final class UsageStore: @unchecked Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var count: Int
        public var lastUsed: Date
    }

    private struct Payload: Codable {
        let version: Int
        let records: [String: Record]

        init(records: [String: Record]) {
            version = 1
            self.records = records
        }
    }

    public static let defaultHalfLife: TimeInterval = 7 * 24 * 60 * 60
    public static let defaultMaximumEntryCount = 500

    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(label: "com.trevorgerald.rev.usage-persistence")
    private var records: [String: Record]
    private let storage: (any UsageHistoryStorage)?
    private let now: @Sendable () -> Date

    /// Half-life used by ``score(_:)``.
    public let halfLife: TimeInterval
    /// Maximum number of distinct emoji retained. Least-recently-used entries are evicted first.
    public let maximumEntryCount: Int

    public init(
        storage: (any UsageHistoryStorage)? = nil,
        maximumEntryCount: Int = UsageStore.defaultMaximumEntryCount,
        halfLife: TimeInterval = UsageStore.defaultHalfLife,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        precondition(maximumEntryCount > 0, "maximumEntryCount must be positive")
        precondition(halfLife > 0 && halfLife.isFinite, "halfLife must be finite and positive")

        self.storage = storage
        self.maximumEntryCount = maximumEntryCount
        self.halfLife = halfLife
        self.now = now

        let loaded = Self.loadRecords(from: storage)
        records = Self.pruned(loaded, to: maximumEntryCount)
        if records.count != loaded.count {
            try? Self.save(records, to: storage)
        }
    }

    /// Compatibility/convenience initializer for callers that have a file URL.
    public convenience init(
        fileURL: URL?,
        maximumEntryCount: Int = UsageStore.defaultMaximumEntryCount,
        halfLife: TimeInterval = UsageStore.defaultHalfLife,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let storage = fileURL.map { JSONFileUsageHistoryStorage(fileURL: $0) }
        self.init(
            storage: storage,
            maximumEntryCount: maximumEntryCount,
            halfLife: halfLife,
            now: now
        )
    }

    /// Default location: `~/Library/Application Support/Rev/usage.json` on macOS.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Rev", isDirectory: true).appendingPathComponent("usage.json")
    }

    public func record(_ emoji: String) {
        guard !emoji.isEmpty else { return }
        lock.lock()
        let timestamp = now()
        var value = records[emoji] ?? Record(count: 0, lastUsed: timestamp)
        if value.count < Int.max { value.count += 1 }
        value.lastUsed = max(value.lastUsed, timestamp)
        records[emoji] = value
        records = Self.pruned(records, to: maximumEntryCount, retaining: emoji)
        let snapshot = records
        if let storage {
            // Enqueue while holding the state lock so concurrent records persist in mutation order.
            // Encoding and atomic file I/O happen off the caller (and event-tap) thread.
            persistenceQueue.async {
                try? Self.save(snapshot, to: storage)
            }
        }
        lock.unlock()
    }

    public func record(for emoji: String) -> Record? {
        lock.lock(); defer { lock.unlock() }
        return records[emoji]
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return records.count
    }

    /// `log2(count + 1) × 0.5^(age / halfLife)`. Returns zero for never-used emoji.
    ///
    /// Logarithmic frequency prevents one heavily-used emoji from accumulating an overwhelming
    /// lead forever, while exponential decay halves its score after each inactive half-life.
    public func score(_ emoji: String) -> Double {
        let timestamp = now()
        lock.lock()
        let value = records[emoji]
        lock.unlock()
        guard let value else { return 0 }
        return score(value, at: timestamp)
    }

    /// A consistent score snapshot for ranking a full result set.
    public func scores() -> [String: Double] {
        let timestamp = now()
        lock.lock()
        let snapshot = records
        lock.unlock()
        return snapshot.mapValues { score($0, at: timestamp) }
    }

    /// Removes all in-memory and persisted usage history.
    ///
    /// The in-memory state is changed only after pending writes and the clearing write succeed, so
    /// a storage failure cannot make old history unexpectedly reappear after relaunch.
    public func clear() throws {
        lock.lock()
        do {
            try persistenceQueue.sync {
                try Self.save([:], to: storage)
            }
            records.removeAll()
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
    }

    /// Waits for writes already queued by ``record(_:)``. Primarily useful at app shutdown and in tests.
    public func flush() {
        lock.lock()
        persistenceQueue.sync {}
        lock.unlock()
    }

    private func score(_ record: Record, at timestamp: Date) -> Double {
        let elapsed = timestamp.timeIntervalSince(record.lastUsed)
        let age = elapsed.isFinite ? max(0, elapsed) : 0
        let frequency = log2(Double(record.count) + 1)
        return frequency * pow(0.5, age / halfLife)
    }

    private static func save(
        _ snapshot: [String: Record],
        to storage: (any UsageHistoryStorage)?
    ) throws {
        guard let storage else { return }
        let data = try JSONEncoder().encode(Payload(records: snapshot))
        try storage.save(data)
    }

    private static func loadRecords(from storage: (any UsageHistoryStorage)?) -> [String: Record] {
        guard let storage, let data = try? storage.load() else { return [:] }
        let decoder = JSONDecoder()
        let decoded: [String: Record]
        if let payload = try? decoder.decode(Payload.self, from: data) {
            decoded = payload.records
        } else if let legacy = try? decoder.decode([String: Record].self, from: data) {
            // Read the original unversioned format so existing users keep their history.
            decoded = legacy
        } else {
            return [:]
        }
        return decoded.filter {
            !$0.key.isEmpty
                && $0.value.count > 0
                && $0.value.lastUsed.timeIntervalSinceReferenceDate.isFinite
        }
    }

    private static func pruned(
        _ records: [String: Record],
        to limit: Int,
        retaining protectedKey: String? = nil
    ) -> [String: Record] {
        guard records.count > limit else { return records }
        let retained = records.sorted { lhs, rhs in
            // A newly-recorded emoji must survive pruning even if an injected clock does not
            // advance (or the system clock moves backwards).
            if lhs.key == protectedKey { return true }
            if rhs.key == protectedKey { return false }
            if lhs.value.lastUsed != rhs.value.lastUsed {
                return lhs.value.lastUsed > rhs.value.lastUsed
            }
            if lhs.value.count != rhs.value.count {
                return lhs.value.count > rhs.value.count
            }
            return lhs.key < rhs.key
        }.prefix(limit)
        return Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
    }
}
