import Foundation
import Testing
@testable import RevCore

@Suite struct LegacyDataMigrationTests {
    @Test func copiesMissingLegacyDataWithoutMovingOrOverwriting() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "LegacyDataMigrationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let defaultsIdentifier = "LegacyDataMigrationTests.\(UUID().uuidString)"
        let legacyDomain = defaultsIdentifier + ".legacy"
        let currentDomain = defaultsIdentifier + ".current"
        let defaults = UserDefaults(suiteName: defaultsIdentifier)!
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: legacyDomain)
            defaults.removePersistentDomain(forName: currentDomain)
            defaults.removeSuite(named: defaultsIdentifier)
        }

        let primary = root.appendingPathComponent("legacy-primary", isDirectory: true)
        let lowercase = root.appendingPathComponent("legacy-lowercase", isDirectory: true)
        let destination = root.appendingPathComponent("Rev", isDirectory: true)
        try write("old snippets", to: primary.appendingPathComponent("snippets.json"))
        try write(
            "old history",
            to: primary.appendingPathComponent("clipboard-history.json")
        )
        try write(
            "image",
            to: primary
                .appendingPathComponent("clipboard-blobs", isDirectory: true)
                .appendingPathComponent("image.png")
        )
        try write("usage", to: lowercase.appendingPathComponent("usage.json"))
        try write(
            "thumbnail",
            to: lowercase
                .appendingPathComponent("clipboard-blobs", isDirectory: true)
                .appendingPathComponent("thumbnail.png")
        )
        try write("new snippets", to: destination.appendingPathComponent("snippets.json"))

        let firstResult = LegacyDataMigration.migrate(
            fileManager: fileManager,
            applicationSupportDirectory: root,
            userDefaults: defaults,
            legacyBundleIdentifier: legacyDomain,
            currentBundleIdentifier: currentDomain,
            legacyDirectoryNames: ["legacy-primary", "legacy-lowercase"],
            currentDirectoryName: "Rev"
        )
        XCTAssertTrue(firstResult.errors.isEmpty)

        try XCTAssertEqual(try read(destination.appendingPathComponent("snippets.json")), "new snippets")
        try XCTAssertEqual(
            try read(destination.appendingPathComponent("clipboard-history.json")),
            "old history"
        )
        try XCTAssertEqual(try read(destination.appendingPathComponent("usage.json")), "usage")
        try XCTAssertEqual(
            try read(
                destination
                    .appendingPathComponent("clipboard-blobs", isDirectory: true)
                    .appendingPathComponent("image.png")
            ),
            "image"
        )
        try XCTAssertEqual(
            try read(
                destination
                    .appendingPathComponent("clipboard-blobs", isDirectory: true)
                    .appendingPathComponent("thumbnail.png")
            ),
            "thumbnail"
        )
        try XCTAssertEqual(
            try read(primary.appendingPathComponent("snippets.json")),
            "old snippets"
        )

        try write("late legacy data", to: primary.appendingPathComponent("late.json"))
        let repeated = LegacyDataMigration.migrate(
            fileManager: fileManager,
            applicationSupportDirectory: root,
            userDefaults: defaults,
            legacyBundleIdentifier: legacyDomain,
            currentBundleIdentifier: currentDomain,
            legacyDirectoryNames: ["legacy-primary", "legacy-lowercase"],
            currentDirectoryName: "Rev"
        )
        XCTAssertEqual(
            repeated,
            LegacyDataMigration.Result(
                copiedPaths: [],
                importedDefaultsKeys: [],
                errors: []
            )
        )
        XCTAssertFalse(
            fileManager.fileExists(atPath: destination.appendingPathComponent("late.json").path)
        )
    }

    @Test func importsOnlyDefaultsMissingFromTheCurrentDomain() {
        let identifier = "LegacyDataMigrationTests.\(UUID().uuidString)"
        let legacyDomain = identifier + ".legacy"
        let currentDomain = identifier + ".current"
        let defaults = UserDefaults(suiteName: identifier)!
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
            defaults.removePersistentDomain(forName: currentDomain)
            defaults.removeSuite(named: identifier)
        }
        defaults.setPersistentDomain(
            [
                "onboardingCompleted": true,
                "skinTone": 3,
                "blocklist": ["com.example.legacy"],
                "toolsHotKeyKey": "space",
            ],
            forName: legacyDomain
        )
        defaults.setPersistentDomain(
            [
                "skinTone": 5,
                "clipboardHistoryEnabled": false,
            ],
            forName: currentDomain
        )

        let imported = LegacyDataMigration.migrateDefaults(
            userDefaults: defaults,
            legacyDomainName: legacyDomain,
            currentDomainName: currentDomain
        )

        XCTAssertEqual(
            imported,
            ["blocklist", "onboardingCompleted", "toolsHotKeyKey"]
        )
        let migrated = defaults.persistentDomain(forName: currentDomain)
        XCTAssertEqual(migrated?["onboardingCompleted"] as? Bool, true)
        XCTAssertEqual(migrated?["skinTone"] as? Int, 5)
        XCTAssertEqual(migrated?["clipboardHistoryEnabled"] as? Bool, false)
        XCTAssertEqual(migrated?["blocklist"] as? [String], ["com.example.legacy"])
        XCTAssertEqual(migrated?["toolsHotKeyKey"] as? String, "space")
        XCTAssertTrue(
            LegacyDataMigration.migrateDefaults(
                userDefaults: defaults,
                legacyDomainName: legacyDomain,
                currentDomainName: currentDomain
            ).isEmpty
        )
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }
}
