import Combine
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--dump") {
            MainActor.assumeIsolated { dumpToTerminal() }
        } else if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            MainActor.assumeIsolated { Snapshot.run(to: args[index + 1]) }
        } else {
            PeepHoleApp.main()
        }
    }

    /// `PeepHole --dump`: print the top network users once, for terminal use.
    @MainActor static func dumpToTerminal() {
        let monitor = NetworkMonitor()
        RunLoop.main.run(until: Date().addingTimeInterval(3.2))
        let grouped = !CommandLine.arguments.contains("--no-group")
        print(String(format: "%-34@ %12@ %12@", "TOTAL" as NSString,
                     Format.rate(monitor.totalDownRate, bits: false) as NSString,
                     Format.rate(monitor.totalUpRate, bits: false) as NSString))
        for row in monitor.rows(mode: .live, groupByApp: grouped, sort: .traffic) {
            print(String(format: "%-34@ %12@ %12@  %@", String(row.name.prefix(34)) as NSString,
                         Format.rate(row.downRate, bits: false) as NSString,
                         Format.rate(row.upRate, bits: false) as NSString,
                         row.subtitle as NSString))
        }
    }
}

struct PeepHoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Owns the menu bar item and its popover. Uses AppKit rather than
/// MenuBarExtra because MenuBarExtra forces the label to be monochrome.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = NetworkMonitor()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppLocation.isTemporary, !AppLocation.confirmRunningFromTemporaryLocation() {
            NSApp.terminate(nil)
            return
        }
        Activity.discardStaleThreshold()
        Updates.shared.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageOnly

        let hosting = NSHostingController(rootView: ContentView(monitor: monitor))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false

        monitor.didUpdate
            .sink { [weak self] in self?.updateStatusItem() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        updateStatusItem()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let defaults = UserDefaults.standard
        let showSpeeds = defaults.object(forKey: "showSpeedsInMenuBar") as? Bool ?? true
        let useBits = defaults.bool(forKey: "useBits")
        let threshold = Activity.threshold
        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        button.image = StatusImage.make(
            up: showSpeeds ? Format.rate(monitor.totalUpRate, bits: useBits) : nil,
            down: showSpeeds ? Format.rate(monitor.totalDownRate, bits: useBits) : nil,
            upActive: monitor.totalUpRate >= threshold,
            downActive: monitor.totalDownRate >= threshold,
            dark: dark)
    }
}

/// Draws the menu bar readout: two lines of speeds with arrows that turn
/// green while traffic is above the activity threshold.
enum StatusImage {
    static func make(up: String?, down: String?, upActive: Bool, downActive: Bool, dark: Bool) -> NSImage {
        let textColor = dark ? NSColor.white : NSColor.black
        let idleArrow = textColor.withAlphaComponent(0.35)
        let green = Activity.nsGreen(dark: dark)

        guard let up, let down else {
            // Speeds hidden: just the two arrows side by side.
            let font = NSFont.systemFont(ofSize: 14, weight: .bold)
            let text = NSMutableAttributedString()
            text.append(NSAttributedString(string: "↓", attributes: [.font: font, .foregroundColor: downActive ? green : idleArrow]))
            text.append(NSAttributedString(string: "↑", attributes: [.font: font, .foregroundColor: upActive ? green : idleArrow]))
            let size = NSSize(width: ceil(text.size().width) + 2, height: 22)
            let image = NSImage(size: size, flipped: false) { rect in
                text.draw(at: NSPoint(x: 1, y: (rect.height - text.size().height) / 2))
                return true
            }
            image.isTemplate = false
            return image
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        let arrowFont = NSFont.systemFont(ofSize: 9.5, weight: .heavy)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right

        func line(_ value: String, _ arrow: String, active: Bool) -> NSAttributedString {
            let result = NSMutableAttributedString(string: value + " ", attributes: [
                .font: font, .foregroundColor: textColor, .paragraphStyle: paragraph,
            ])
            result.append(NSAttributedString(string: arrow, attributes: [
                .font: arrowFont, .foregroundColor: active ? green : idleArrow, .paragraphStyle: paragraph,
            ]))
            return result
        }

        let upLine = line(up, "↑", active: upActive)
        let downLine = line(down, "↓", active: downActive)
        let image = NSImage(size: NSSize(width: 64, height: 22), flipped: false) { rect in
            let lineHeight = rect.height / 2
            upLine.draw(in: NSRect(x: 0, y: lineHeight - 1, width: rect.width, height: lineHeight))
            downLine.draw(in: NSRect(x: 0, y: -1, width: rect.width, height: lineHeight))
            return true
        }
        image.isTemplate = false
        return image
    }
}
