import Foundation
import Testing
@testable import MacmojiCore

@Suite struct ClipboardHistoryTests {
    @Test func classifiesPlainTextLinksAndColors() {
        XCTAssertEqual(
            ClipboardCaptureContent.classify(text: "https://example.com/path"),
            .link("https://example.com/path")
        )
        XCTAssertEqual(ClipboardCaptureContent.classify(text: " #a1b2c3\n"), .color("#A1B2C3"))
        XCTAssertEqual(ClipboardCaptureContent.classify(text: "hello world"), .text("hello world"))
        XCTAssertEqual(ClipboardCaptureContent.classify(text: ""), nil)
    }

    @Test func privacySkipsSensitiveTypesAndExcludedApps() {
        XCTAssertFalse(ClipboardPrivacy.shouldCapture(
            typeIdentifiers: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
            sourceBundleIdentifier: "com.apple.TextEdit",
            excludedBundleIdentifiers: []
        ))
        XCTAssertFalse(ClipboardPrivacy.shouldCapture(
            typeIdentifiers: ["public.utf8-plain-text"],
            sourceBundleIdentifier: "COM.BITWARDEN.DESKTOP",
            excludedBundleIdentifiers: ClipboardPrivacy.defaultExcludedBundleIdentifiers
        ))
        XCTAssertTrue(ClipboardPrivacy.shouldCapture(
            typeIdentifiers: ["public.utf8-plain-text"],
            sourceBundleIdentifier: "com.apple.TextEdit",
            excludedBundleIdentifiers: ClipboardPrivacy.defaultExcludedBundleIdentifiers
        ))
    }

    @Test func duplicateMovesToTopAndPreservesPin() {
        let clock = ClipboardTestClock()
        let store = ClipboardHistoryStore(now: { clock.now })
        let textEdit = ClipboardSource(bundleIdentifier: "com.apple.TextEdit", name: "TextEdit")
        let notes = ClipboardSource(bundleIdentifier: "com.apple.Notes", name: "Notes")

        let first = store.record(.text("first"), source: textEdit)!
        clock.advance(by: 1)
        store.record(.text("second"), source: notes)
        XCTAssertEqual(store.allItems().map(\.content.displayText), ["second", "first"])

        store.togglePinned(id: first.id)
        clock.advance(by: 1)
        let duplicate = store.record(.text("first"), source: notes)!

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.allItems().first?.id, first.id)
        XCTAssertTrue(duplicate.isPinned)
        XCTAssertEqual(duplicate.source, notes)
        XCTAssertEqual(duplicate.copiedAt, clock.now)
    }

    @Test func searchCoversContentFileNamesSourcesFuzzyAndFilters() {
        let clock = ClipboardTestClock()
        let store = ClipboardHistoryStore(now: { clock.now })
        store.record(
            .text("hello world"),
            source: ClipboardSource(bundleIdentifier: "com.apple.Notes", name: "Notes")
        )
        clock.advance(by: 1)
        store.record(
            .link("https://cursor.com/docs"),
            source: ClipboardSource(bundleIdentifier: "com.apple.Safari", name: "Safari")
        )
        clock.advance(by: 1)
        store.record(
            .files(["/tmp/quarterly-report.pdf"]),
            source: ClipboardSource(bundleIdentifier: "com.apple.finder", name: "Finder")
        )
        clock.advance(by: 1)
        store.record(
            .image(
                data: Data([1, 2, 3]),
                thumbnailData: nil,
                format: .png,
                pixelWidth: 10,
                pixelHeight: 10
            ),
            source: ClipboardSource(bundleIdentifier: "com.apple.Preview", name: "Preview")
        )

        XCTAssertEqual(store.search("hello").map(\.kind), [.text])
        XCTAssertEqual(store.search("qtrly").map(\.kind), [.files])
        XCTAssertEqual(store.search("safari").map(\.kind), [.link])
        XCTAssertEqual(store.search("", filter: .links).map(\.kind), [.link])
        XCTAssertEqual(store.search("", filter: .files).map(\.kind), [.files])
        XCTAssertEqual(store.search("", filter: .images).map(\.kind), [.image])
    }

    @Test func retentionAndCapNeverPrunePinnedItems() {
        let clock = ClipboardTestClock()
        let store = ClipboardHistoryStore(
            configuration: ClipboardHistoryConfiguration(
                retention: .oneDay,
                maximumUnpinnedEntries: 2
            ),
            now: { clock.now }
        )
        let source = ClipboardSource(bundleIdentifier: nil, name: nil)

        let pinned = store.record(.text("pinned-old"), source: source)!
        store.togglePinned(id: pinned.id)
        clock.advance(by: 2 * 24 * 60 * 60)
        store.record(.text("one"), source: source)
        clock.advance(by: 1)
        store.record(.text("two"), source: source)
        clock.advance(by: 1)
        store.record(.text("three"), source: source)

        XCTAssertEqual(store.allItems().map(\.content.displayText), ["pinned-old", "three", "two"])
        XCTAssertTrue(store.allItems().first?.isPinned == true)
    }

    @Test func searchingPrunesItemsThatExpiredWhileAppWasIdle() {
        let clock = ClipboardTestClock()
        let store = ClipboardHistoryStore(
            configuration: ClipboardHistoryConfiguration(retention: .oneDay),
            now: { clock.now }
        )
        store.record(
            .text("expired"),
            source: ClipboardSource(bundleIdentifier: nil, name: nil)
        )
        clock.advance(by: 2 * 24 * 60 * 60)

        XCTAssertTrue(store.search("").isEmpty)
        XCTAssertEqual(store.count, 0)
    }

    @Test func persistenceRoundTripIncludesImageBlobsAndCleansDeletedBlobs() {
        let storage = MemoryClipboardHistoryStorage()
        let source = ClipboardSource(bundleIdentifier: "test.app", name: "Test")
        let image = Data([0x89, 0x50, 0x4e, 0x47])
        let thumbnail = Data([0x01, 0x02])
        let first = ClipboardHistoryStore(storage: storage)

        let recorded = first.record(
            .image(
                data: image,
                thumbnailData: thumbnail,
                format: .png,
                pixelWidth: 640,
                pixelHeight: 480
            ),
            source: source
        )!
        first.flush()
        let indexObject = try? JSONSerialization.jsonObject(with: storage.indexData ?? Data())
            as? [String: Any]
        XCTAssertEqual(indexObject?["version"] as? Int, 1)

        let reloaded = ClipboardHistoryStore(storage: storage)
        XCTAssertEqual(reloaded.count, 1)
        guard case .image(let persistedImage)? = reloaded.item(id: recorded.id)?.content else {
            Issue.record("Expected a persisted image")
            return
        }
        XCTAssertEqual(reloaded.blobData(named: persistedImage.blobName), image)
        XCTAssertEqual(reloaded.blobData(named: persistedImage.thumbnailBlobName!), thumbnail)

        XCTAssertTrue(reloaded.delete(id: recorded.id))
        reloaded.flush()
        XCTAssertTrue(storage.blobs.isEmpty)
    }

    @Test func clearKeepsPinnedItems() {
        let store = ClipboardHistoryStore()
        let source = ClipboardSource(bundleIdentifier: nil, name: nil)
        let pinned = store.record(.text("keep"), source: source)!
        store.togglePinned(id: pinned.id)
        store.record(.text("remove"), source: source)

        store.clearUnpinned()

        XCTAssertEqual(store.allItems().map(\.content.displayText), ["keep"])
        XCTAssertTrue(store.allItems().first?.isPinned == true)
    }
}

private final class ClipboardTestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

private final class MemoryClipboardHistoryStorage: ClipboardHistoryStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var index: Data?
    private var storedBlobs: [String: Data] = [:]

    var blobs: [String: Data] {
        lock.lock(); defer { lock.unlock() }
        return storedBlobs
    }

    var indexData: Data? {
        lock.lock(); defer { lock.unlock() }
        return index
    }

    func loadIndex() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return index
    }

    func saveIndex(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        index = data
    }

    func saveBlob(_ data: Data, named name: String) throws {
        lock.lock(); defer { lock.unlock() }
        storedBlobs[name] = data
    }

    func loadBlob(named name: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = storedBlobs[name] else { throw StorageError.missingBlob }
        return data
    }

    func removeBlobs(except retainedNames: Set<String>) throws {
        lock.lock(); defer { lock.unlock() }
        storedBlobs = storedBlobs.filter { retainedNames.contains($0.key) }
    }

    private enum StorageError: Error {
        case missingBlob
    }
}
