import Foundation
import Dispatch

public protocol ClipboardHistoryStorage: Sendable {
    func loadIndex() throws -> Data?
    func saveIndex(_ data: Data) throws
    func saveBlob(_ data: Data, named name: String) throws
    func loadBlob(named name: String) throws -> Data
    func removeBlobs(except retainedNames: Set<String>) throws
}

public struct JSONFileClipboardHistoryStorage: ClipboardHistoryStorage, @unchecked Sendable {
    public let baseURL: URL
    public let indexURL: URL
    public let blobsURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
        indexURL = baseURL.appendingPathComponent("clipboard-history.json")
        blobsURL = baseURL.appendingPathComponent("clipboard-blobs", isDirectory: true)
    }

    public static func defaultBaseURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return applicationSupport.appendingPathComponent("Rev", isDirectory: true)
    }

    public func loadIndex() throws -> Data? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return nil }
        return try Data(contentsOf: indexURL)
    }

    public func saveIndex(_ data: Data) throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try data.write(to: indexURL, options: .atomic)
    }

    public func saveBlob(_ data: Data, named name: String) throws {
        try FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        try data.write(to: blobsURL.appendingPathComponent(name), options: .atomic)
    }

    public func loadBlob(named name: String) throws -> Data {
        try Data(contentsOf: blobsURL.appendingPathComponent(name))
    }

    public func removeBlobs(except retainedNames: Set<String>) throws {
        guard FileManager.default.fileExists(atPath: blobsURL.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(
            at: blobsURL,
            includingPropertiesForKeys: nil
        ) where !retainedNames.contains(url.lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

public final class ClipboardHistoryStore: @unchecked Sendable {
    private struct Payload: Codable {
        let version: Int
        let items: [ClipboardItem]

        init(items: [ClipboardItem]) {
            version = 1
            self.items = items
        }
    }

    private struct PendingBlob: Sendable {
        let name: String
        let data: Data
    }

    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(
        label: "com.trevorgerald.rev.clipboard-history-persistence",
        qos: .utility
    )
    private let storage: (any ClipboardHistoryStorage)?
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private var configuration: ClipboardHistoryConfiguration
    private var storedItems: [ClipboardItem]

    public init(
        storage: (any ClipboardHistoryStorage)? = nil,
        configuration: ClipboardHistoryConfiguration = ClipboardHistoryConfiguration(),
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.storage = storage
        self.configuration = configuration
        self.now = now
        self.makeID = makeID

        let loaded = Self.loadItems(from: storage)
        storedItems = Self.pruned(loaded, configuration: configuration, at: now())
        storedItems = Self.sorted(storedItems)
        if storedItems != loaded {
            schedulePersistence(items: storedItems, blobs: [])
        }
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storedItems.count
    }

    public func allItems() -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        return Self.sorted(storedItems)
    }

    public func item(id: UUID) -> ClipboardItem? {
        lock.lock(); defer { lock.unlock() }
        return storedItems.first { $0.id == id }
    }

    @discardableResult
    public func record(
        _ captured: ClipboardCaptureContent,
        source: ClipboardSource
    ) -> ClipboardItem? {
        guard let materialized = Self.materialize(captured) else { return nil }

        lock.lock()
        let timestamp = now()
        let existingIndex = storedItems.firstIndex {
            $0.deduplicationKey == materialized.deduplicationKey
        }
        let item: ClipboardItem
        if let existingIndex {
            var existing = storedItems.remove(at: existingIndex)
            existing.content = materialized.content
            existing.source = source
            existing.copiedAt = max(existing.copiedAt, timestamp)
            item = existing
        } else {
            item = ClipboardItem(
                id: makeID(),
                content: materialized.content,
                source: source,
                copiedAt: timestamp,
                deduplicationKey: materialized.deduplicationKey
            )
        }
        storedItems.append(item)
        storedItems = Self.pruned(storedItems, configuration: configuration, at: timestamp)
        storedItems = Self.sorted(storedItems)
        let snapshot = storedItems
        schedulePersistence(items: snapshot, blobs: materialized.blobs)
        lock.unlock()
        return snapshot.first { $0.id == item.id }
    }

    public func search(
        _ query: String,
        filter: ClipboardTypeFilter = .all
    ) -> [ClipboardItem] {
        prune()
        let snapshot = allItems()
        return ClipboardHistorySearch.results(in: snapshot, query: query, filter: filter)
    }

    @discardableResult
    public func togglePinned(id: UUID) -> ClipboardItem? {
        lock.lock()
        guard let index = storedItems.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return nil
        }
        storedItems[index].isPinned.toggle()
        storedItems = Self.pruned(storedItems, configuration: configuration, at: now())
        storedItems = Self.sorted(storedItems)
        let snapshot = storedItems
        let updated = snapshot.first { $0.id == id }
        schedulePersistence(items: snapshot, blobs: [])
        lock.unlock()
        return updated
    }

    @discardableResult
    public func delete(id: UUID) -> Bool {
        lock.lock()
        let originalCount = storedItems.count
        storedItems.removeAll { $0.id == id }
        guard storedItems.count != originalCount else {
            lock.unlock()
            return false
        }
        let snapshot = storedItems
        schedulePersistence(items: snapshot, blobs: [])
        lock.unlock()
        return true
    }

    /// Clears unpinned entries and preserves pinned entries.
    public func clearUnpinned() {
        lock.lock()
        storedItems.removeAll { !$0.isPinned }
        storedItems = Self.sorted(storedItems)
        let snapshot = storedItems
        schedulePersistence(items: snapshot, blobs: [])
        lock.unlock()
    }

    public func updateConfiguration(_ configuration: ClipboardHistoryConfiguration) {
        lock.lock()
        self.configuration = configuration
        storedItems = Self.pruned(storedItems, configuration: configuration, at: now())
        storedItems = Self.sorted(storedItems)
        let snapshot = storedItems
        schedulePersistence(items: snapshot, blobs: [])
        lock.unlock()
    }

    public func prune() {
        lock.lock()
        let updated = Self.sorted(Self.pruned(
            storedItems,
            configuration: configuration,
            at: now()
        ))
        guard updated != storedItems else {
            lock.unlock()
            return
        }
        storedItems = updated
        let snapshot = storedItems
        schedulePersistence(items: snapshot, blobs: [])
        lock.unlock()
    }

    public func blobData(named name: String) -> Data? {
        try? storage?.loadBlob(named: name)
    }

    public func flush() {
        lock.lock()
        persistenceQueue.sync {}
        lock.unlock()
    }

    private func schedulePersistence(items: [ClipboardItem], blobs: [PendingBlob]) {
        guard let storage else { return }
        let referencedBlobs = Set(items.flatMap { $0.content.blobNames })
        persistenceQueue.async {
            do {
                for blob in blobs {
                    try storage.saveBlob(blob.data, named: blob.name)
                }
                let data = try JSONEncoder().encode(Payload(items: items))
                try storage.saveIndex(data)
                try storage.removeBlobs(except: referencedBlobs)
            } catch {
                // Clipboard history is best-effort; never interfere with the system clipboard.
            }
        }
    }

    private static func loadItems(
        from storage: (any ClipboardHistoryStorage)?
    ) -> [ClipboardItem] {
        guard let storage,
              let data = try? storage.loadIndex(),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1 else { return [] }

        var seenIDs = Set<UUID>()
        var seenKeys = Set<String>()
        return payload.items.filter {
            seenIDs.insert($0.id).inserted
                && seenKeys.insert($0.deduplicationKey).inserted
        }
    }

    private static func sorted(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.copiedAt != $1.copiedAt { return $0.copiedAt > $1.copiedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func pruned(
        _ items: [ClipboardItem],
        configuration: ClipboardHistoryConfiguration,
        at timestamp: Date
    ) -> [ClipboardItem] {
        let cutoff = configuration.retention.interval.map {
            timestamp.addingTimeInterval(-$0)
        }
        let pinned = items.filter(\.isPinned)
        let unpinned = items.filter {
            guard !$0.isPinned else { return false }
            guard let cutoff else { return true }
            return $0.copiedAt >= cutoff
        }
        return pinned + sorted(Array(
            sorted(unpinned).prefix(configuration.maximumUnpinnedEntries)
        ))
    }

    private static func materialize(
        _ captured: ClipboardCaptureContent
    ) -> (content: ClipboardContent, deduplicationKey: String, blobs: [PendingBlob])? {
        switch captured {
        case .text(let value):
            guard !value.isEmpty else { return nil }
            let hash = StableClipboardHash.string(value)
            return (.text(value), "text:\(hash)", [])

        case .link(let value):
            guard !value.isEmpty else { return nil }
            let hash = StableClipboardHash.string(value)
            return (.link(value), "link:\(hash)", [])

        case .files(let values):
            guard !values.isEmpty else { return nil }
            let hash = StableClipboardHash.string(values.joined(separator: "\u{0}"))
            return (.files(values), "files:\(hash)", [])

        case .color(let value):
            guard let normalized = ClipboardColor.normalizedHex(value) else { return nil }
            let hash = StableClipboardHash.string(normalized)
            return (.color(normalized), "color:\(hash)", [])

        case .image(let data, let thumbnailData, let format, let width, let height):
            guard !data.isEmpty else { return nil }
            let hash = StableClipboardHash.data(data)
            let blobName = "image-\(hash).\(format.fileExtension)"
            let thumbnailName = thumbnailData.map { _ in "thumbnail-\(hash).png" }
            let image = ClipboardImage(
                blobName: blobName,
                thumbnailBlobName: thumbnailName,
                format: format,
                pixelWidth: width,
                pixelHeight: height,
                byteCount: data.count,
                contentHash: hash
            )
            var blobs = [PendingBlob(name: blobName, data: data)]
            if let thumbnailData, let thumbnailName {
                blobs.append(PendingBlob(name: thumbnailName, data: thumbnailData))
            }
            return (.image(image), "image:\(hash)", blobs)
        }
    }
}

private enum StableClipboardHash {
    private static let offset: UInt64 = 14_695_981_039_346_656_037
    private static let prime: UInt64 = 1_099_511_628_211

    static func string(_ value: String) -> String {
        hash(value.utf8)
    }

    static func data(_ value: Data) -> String {
        hash(value)
    }

    private static func hash<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        var result = offset
        for byte in bytes {
            result ^= UInt64(byte)
            result &*= prime
        }
        return String(result, radix: 16)
    }
}
