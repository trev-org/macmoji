#if os(macOS)
import AppKit
import MacmojiCore

/// Polls NSPasteboard without requiring Accessibility permission.
@MainActor
final class ClipboardMonitor {
    var onCapture: (@MainActor (ClipboardCaptureContent, ClipboardSource) -> Void)?
    var isCaptureEnabled: (@MainActor () -> Bool) = { true }
    var excludedBundleIdentifiers: (@MainActor () -> [String]) = { [] }

    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount = 0
    private var ignoredChangeCounts = Set<Int>()
    private var sourceApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        sourceApplication = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Check before changing the source so a copy immediately followed by an app switch
                // is attributed to the app where the copy occurred.
                self.poll(sourceApplication: self.sourceApplication)
                self.sourceApplication = notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication
            }
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.poll(sourceApplication: self.sourceApplication)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    func ignore(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    func capturePendingChange() {
        poll(sourceApplication: sourceApplication)
    }

    private func poll(sourceApplication application: NSRunningApplication?) {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        if ignoredChangeCounts.remove(changeCount) != nil { return }
        guard isCaptureEnabled() else { return }

        let items = pasteboard.pasteboardItems ?? []
        let typeIdentifiers = (pasteboard.types ?? []).map(\.rawValue)
            + items.flatMap { $0.types.map(\.rawValue) }
        let source = ClipboardSource(
            bundleIdentifier: application?.bundleIdentifier,
            name: application?.localizedName
        )
        guard ClipboardPrivacy.shouldCapture(
            typeIdentifiers: typeIdentifiers,
            sourceBundleIdentifier: source.bundleIdentifier,
            excludedBundleIdentifiers: excludedBundleIdentifiers()
        ), let captured = capture(from: items) else { return }

        onCapture?(captured, source)
    }

    private func capture(from items: [NSPasteboardItem]) -> ClipboardCaptureContent? {
        let filePaths = items.compactMap { item -> String? in
            guard let value = item.string(forType: .fileURL),
                  let url = URL(string: value), url.isFileURL else { return nil }
            return url.path
        }
        if !filePaths.isEmpty { return .files(filePaths) }

        if let data = items.lazy.compactMap({ $0.data(forType: .png) }).first {
            return imageCapture(data: data, format: .png)
        }
        if let data = items.lazy.compactMap({ $0.data(forType: .tiff) }).first {
            return imageCapture(data: data, format: .tiff)
        }
        if let value = items.lazy.compactMap({ $0.string(forType: .URL) }).first {
            return .link(value)
        }
        if let value = items.lazy.compactMap({ $0.string(forType: .string) }).first {
            return ClipboardCaptureContent.classify(text: value)
        }
        return nil
    }

    private func imageCapture(
        data: Data,
        format: ClipboardImageFormat
    ) -> ClipboardCaptureContent? {
        guard data.count <= ClipboardImageProcessor.maximumImageBytes else { return nil }
        return .image(
            data: data,
            thumbnailData: nil,
            format: format,
            pixelWidth: nil,
            pixelHeight: nil
        )
    }
}
#endif
