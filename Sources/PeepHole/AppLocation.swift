import AppKit

/// Detects PeepHole running somewhere temporary: straight from the mounted disk image,
/// or from a Gatekeeper "translocated" copy (an app opened without being moved out
/// of Downloads). Login items and updates would point at a path that goes away.
enum AppLocation {
    static var isTemporary: Bool {
        isTemporary(path: Bundle.main.bundlePath)
    }

    static func isTemporary(path: String) -> Bool {
        path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    /// Asks the user to install properly. Returns false if they chose to quit.
    @MainActor static func confirmRunningFromTemporaryLocation() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move PeepHole to Applications"
        alert.informativeText = "PeepHole is running from the disk image or Downloads folder. "
            + "Quit, drag PeepHole into your Applications folder, and open it from there "
            + "so Launch at login and updates work."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep Running")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
