import Foundation
import Testing
@testable import MacmojiCore

@Suite struct UsageStoreTests {
    @Test func recordingUpdatesCountAndLastUsed() {
        let clock = UsageTestClock()
        let store = UsageStore(now: { clock.now })

        store.record("🔥")
        clock.advance(by: 60)
        store.record("🔥")

        XCTAssertEqual(
            store.record(for: "🔥"),
            UsageStore.Record(count: 2, lastUsed: clock.now)
        )
        XCTAssertEqual(store.count, 1)
    }

    @Test func frequencyIsLogarithmicAndRecencyDecaysByHalfLife() {
        let clock = UsageTestClock()
        let store = UsageStore(halfLife: 7 * 24 * 60 * 60, now: { clock.now })

        store.record("🔥")
        store.record("🔥")
        store.record("🔥")
        XCTAssertEqual(store.score("🔥"), 2, accuracy: 1e-9) // log2(3 + 1)

        clock.advance(by: store.halfLife)
        XCTAssertEqual(store.score("🔥"), 1, accuracy: 1e-9)
        XCTAssertEqual(store.score("never-used"), 0)
    }

    @Test func lastUsedNeverRegressesWhenClockMovesBackwards() {
        let clock = UsageTestClock()
        let store = UsageStore(now: { clock.now })
        store.record("🔥")
        let firstTimestamp = clock.now

        clock.advance(by: -60)
        store.record("🔥")

        XCTAssertEqual(store.record(for: "🔥")?.lastUsed, firstTimestamp)
        XCTAssertEqual(store.record(for: "🔥")?.count, 2)
    }

    @Test func persistenceRoundTripUsesInjectedStorage() {
        let storage = MemoryUsageHistoryStorage()
        let clock = UsageTestClock()
        let first = UsageStore(storage: storage, now: { clock.now })

        first.record("👍")
        clock.advance(by: 120)
        first.record("👍")
        first.record("🔥")
        first.flush()

        let reloaded = UsageStore(storage: storage, now: { clock.now })
        XCTAssertEqual(
            reloaded.record(for: "👍"),
            UsageStore.Record(count: 2, lastUsed: clock.now)
        )
        XCTAssertEqual(reloaded.record(for: "🔥")?.count, 1)
        XCTAssertTrue(storage.data != nil)
    }

    @Test func clearRemovesMemoryAndPersistedHistory() throws {
        let storage = MemoryUsageHistoryStorage()
        let store = UsageStore(storage: storage)
        store.record("🔥")
        store.record("👍")

        try store.clear()

        XCTAssertEqual(store.count, 0)
        XCTAssertEqual(store.record(for: "🔥"), nil)
        XCTAssertEqual(UsageStore(storage: storage).count, 0)
    }

    @Test func historyCapEvictsLeastRecentlyUsedEntry() {
        let storage = MemoryUsageHistoryStorage()
        let clock = UsageTestClock()
        let store = UsageStore(
            storage: storage,
            maximumEntryCount: 2,
            now: { clock.now }
        )

        store.record("oldest")
        clock.advance(by: 1)
        store.record("middle")
        clock.advance(by: 1)
        store.record("newest")

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.record(for: "oldest"), nil)
        XCTAssertEqual(store.record(for: "middle")?.count, 1)
        XCTAssertEqual(store.record(for: "newest")?.count, 1)
        store.flush()
        XCTAssertEqual(UsageStore(storage: storage, maximumEntryCount: 2).count, 2)
    }

    @Test func clearFailureKeepsCurrentAndPersistedHistory() {
        let storage = MemoryUsageHistoryStorage()
        let store = UsageStore(storage: storage)
        store.record("🔥")
        store.flush()
        storage.shouldFailSave = true

        var didThrow = false
        do {
            try store.clear()
        } catch {
            didThrow = true
        }

        XCTAssertTrue(didThrow)
        XCTAssertEqual(store.record(for: "🔥")?.count, 1)
        XCTAssertEqual(UsageStore(storage: storage).record(for: "🔥")?.count, 1)
    }
}

private final class UsageTestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_700_000_000)

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

private final class MemoryUsageHistoryStorage: UsageHistoryStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?
    private var failsSaves = false

    var shouldFailSave: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return failsSaves
        }
        set {
            lock.lock(); defer { lock.unlock() }
            failsSaves = newValue
        }
    }

    var data: Data? {
        lock.lock(); defer { lock.unlock() }
        return storedData
    }

    func load() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storedData
    }

    func save(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if failsSaves { throw StorageError.saveFailed }
        storedData = data
    }

    private enum StorageError: Error {
        case saveFailed
    }
}
