import AppKit
import SwiftUI

/// `NetHog --snapshot <file.png>`: render the popover to an image after a few
/// seconds of live sampling. Handy for checking the UI without clicking around.
enum Snapshot {
    @MainActor static func run(to path: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let monitor = NetworkMonitor()
        let host = NSHostingView(rootView: ContentView(monitor: monitor)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 400, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(4.5))
        host.layoutSubtreeIfNeeded()
        window.setContentSize(host.fittingSize)

        let bounds = host.bounds
        guard let rep = host.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        host.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))

        // Menu bar readout on a dark and a light strip, as it would appear in the menu bar.
        for dark in [true, false] {
            let bar = StatusImage.make(up: Format.rate(monitor.totalUpRate, bits: false),
                                       down: Format.rate(monitor.totalDownRate, bits: false),
                                       upActive: monitor.totalUpRate >= Activity.threshold,
                                       downActive: monitor.totalDownRate >= Activity.threshold,
                                       dark: dark)
            let strip = NSImage(size: NSSize(width: 80, height: 24), flipped: false) { rect in
                (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                rect.fill()
                bar.draw(in: NSRect(x: 8, y: 1, width: bar.size.width, height: bar.size.height))
                return true
            }
            if let tiff = strip.tiffRepresentation, let barRep = NSBitmapImageRep(data: tiff) {
                let barPath = (path as NSString).deletingPathExtension + "-menubar-\(dark ? "dark" : "light").png"
                try? barRep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: barPath))
            }
        }
    }
}
