import Foundation

/// Copies data and preferences from the app's previous identity without overwriting Rev data.
public enum LegacyDataMigration {
    public static let legacyBundleIdentifier = "com.trevorgerald.macmoji"
    public static let currentBundleIdentifier = "com.trevorgerald.rev"
    public static let legacyApplicationSupportDirectoryNames = ["Macmoji", "macmoji"]
    public static let currentApplicationSupportDirectoryName = "Rev"
    static let migrationVersionKey = "legacyDataMigrationVersion"
    static let currentMigrationVersion = 1

    public struct Result: Equatable, Sendable {
        public let copiedPaths: [String]
        public let importedDefaultsKeys: [String]
        public let errors: [String]

        public init(
            copiedPaths: [String],
            importedDefaultsKeys: [String],
            errors: [String]
        ) {
            self.copiedPaths = copiedPaths
            self.importedDefaultsKeys = importedDefaultsKeys
            self.errors = errors
        }
    }

    /// Runs the migration. Existing Rev files and preference keys always win.
    ///
    /// The operation is safe to repeat: legacy data is copied, never moved, and an existing
    /// destination is never replaced.
    @discardableResult
    public static func migrate(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) -> Result {
        let applicationSupport = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return migrate(
            fileManager: fileManager,
            applicationSupportDirectory: applicationSupport,
            userDefaults: userDefaults,
            legacyBundleIdentifier: legacyBundleIdentifier,
            currentBundleIdentifier: currentBundleIdentifier,
            legacyDirectoryNames: legacyApplicationSupportDirectoryNames,
            currentDirectoryName: currentApplicationSupportDirectoryName
        )
    }

    static func migrate(
        fileManager: FileManager,
        applicationSupportDirectory: URL,
        userDefaults: UserDefaults,
        legacyBundleIdentifier: String,
        currentBundleIdentifier: String,
        legacyDirectoryNames: [String],
        currentDirectoryName: String
    ) -> Result {
        let currentDefaults = userDefaults.persistentDomain(
            forName: currentBundleIdentifier
        ) ?? [:]
        if (currentDefaults[migrationVersionKey] as? Int ?? 0) >= currentMigrationVersion {
            return Result(copiedPaths: [], importedDefaultsKeys: [], errors: [])
        }

        let destination = applicationSupport.appendingPathComponent(
            currentDirectoryName,
            isDirectory: true
        )

        var copiedPaths: [String] = []
        var errors: [String] = []
        for directoryName in legacyDirectoryNames {
            let source = applicationSupport.appendingPathComponent(
                directoryName,
                isDirectory: true
            )
            do {
                copiedPaths.append(contentsOf: try copyMissingItem(
                    from: source,
                    to: destination,
                    fileManager: fileManager
                ))
            } catch {
                errors.append(
                    "Could not copy \(source.path) to \(destination.path): "
                        + error.localizedDescription
                )
            }
        }

        let importedDefaultsKeys = migrateDefaults(
            userDefaults: userDefaults,
            legacyDomainName: legacyBundleIdentifier,
            currentDomainName: currentBundleIdentifier
        )
        if errors.isEmpty {
            markCompleted(
                userDefaults: userDefaults,
                currentDomainName: currentBundleIdentifier
            )
        }
        return Result(
            copiedPaths: copiedPaths.sorted(),
            importedDefaultsKeys: importedDefaultsKeys,
            errors: errors
        )
    }

    static func markCompleted(
        userDefaults: UserDefaults,
        currentDomainName: String
    ) {
        var current = userDefaults.persistentDomain(forName: currentDomainName) ?? [:]
        current[migrationVersionKey] = currentMigrationVersion
        userDefaults.setPersistentDomain(current, forName: currentDomainName)
    }

    /// Returns and persists only legacy preference keys that Rev has not stored itself.
    @discardableResult
    static func migrateDefaults(
        userDefaults: UserDefaults,
        legacyDomainName: String,
        currentDomainName: String
    ) -> [String] {
        let legacy = userDefaults.persistentDomain(forName: legacyDomainName) ?? [:]
        var current = userDefaults.persistentDomain(forName: currentDomainName) ?? [:]
        let importedKeys = legacy.keys.filter { !current.keys.contains($0) }.sorted()
        guard !importedKeys.isEmpty else { return [] }

        for key in importedKeys {
            current[key] = legacy[key]
        }
        userDefaults.setPersistentDomain(current, forName: currentDomainName)
        return importedKeys
    }

    /// Recursively copies a source item when its destination is missing.
    ///
    /// When both items are directories, missing descendants are merged so an earlier partial
    /// Rev launch cannot prevent the remaining legacy files or image blobs from migrating.
    static func copyMissingItem(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws -> [String] {
        var sourceIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: source.path,
            isDirectory: &sourceIsDirectory
        ) else {
            return []
        }

        var destinationIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: destination.path,
            isDirectory: &destinationIsDirectory
        ) else {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
            return [destination.path]
        }

        guard sourceIsDirectory.boolValue, destinationIsDirectory.boolValue else {
            return []
        }

        var copiedPaths: [String] = []
        let children = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        for child in children {
            copiedPaths.append(contentsOf: try copyMissingItem(
                from: child,
                to: destination.appendingPathComponent(child.lastPathComponent),
                fileManager: fileManager
            ))
        }
        return copiedPaths
    }
}
