import Foundation

/// Frecency store: counts and last-use times, persisted as JSON in a local file.
public final class UsageStore: @unchecked Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var count: Int
        public var lastUsed: Date
    }

    private let lock = NSLock()
    private var records: [String: Record]
    private let fileURL: URL?
    private let now: @Sendable () -> Date
    /// Half-life of the recency decay.
    public var halfLife: TimeInterval = 14 * 24 * 3600

    public init(fileURL: URL?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.now = now
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    /// Default location: ~/Library/Application Support/macmoji/usage.json (or XDG-ish on Linux).
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("macmoji", isDirectory: true).appendingPathComponent("usage.json")
    }

    public func record(_ emoji: String) {
        lock.lock()
        var r = records[emoji] ?? Record(count: 0, lastUsed: now())
        r.count += 1
        r.lastUsed = now()
        records[emoji] = r
        let snapshot = records
        lock.unlock()
        save(snapshot)
    }

    public func record(for emoji: String) -> Record? {
        lock.lock(); defer { lock.unlock() }
        return records[emoji]
    }

    /// count × 0.5^(age / halfLife). 0 for never-used emoji.
    public func score(_ emoji: String) -> Double {
        lock.lock(); let r = records[emoji]; lock.unlock()
        guard let r else { return 0 }
        let age = max(0, now().timeIntervalSince(r.lastUsed))
        return Double(r.count) * pow(0.5, age / halfLife)
    }

    private func save(_ snapshot: [String: Record]) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            // Usage data is best-effort.
        }
    }
}
