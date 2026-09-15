import AppKit
import Combine
import Sparkle

/// Sparkle auto-updates. The feed URL and signing key live in Info.plist.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    @Published private(set) var canCheck = false
    private let controller = SPUStandardUpdaterController(startingUpdater: false,
                                                          updaterDelegate: nil,
                                                          userDriverDelegate: nil)

    /// Only a packaged app (with a feed URL) can update; `swift run` builds can't.
    var isAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    }

    func start() {
        guard isAvailable else { return }
        controller.startUpdater()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheck)
    }

    func checkForUpdates() {
        // NetHog has no Dock icon, so bring it forward or the update window opens behind other apps.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
