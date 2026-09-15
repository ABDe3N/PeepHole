import AppKit
import SwiftUI

/// "Something is really transferring" threshold, below which traffic counts
/// as background chatter. Arrows turn green above it.
enum Activity {
    static let thresholdKey = "activityThreshold"
    static let defaultThreshold: Double = 100_000 // bytes per second; nothing below this is colored
    static let choices: [Double] = [100_000, 250_000, 500_000, 1_000_000]

    static var threshold: Double {
        let value = UserDefaults.standard.double(forKey: thresholdKey)
        return choices.contains(value) ? value : defaultThreshold
    }

    /// Drops a saved threshold that is no longer offered (e.g. an old 50 KB/s).
    static func discardStaleThreshold() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: thresholdKey) != nil,
           !choices.contains(defaults.double(forKey: thresholdKey)) {
            defaults.removeObject(forKey: thresholdKey)
        }
    }

    /// Apps whose traffic stays below this floor never get a row.
    static let floorKey = "hideBelow"
    static let defaultFloor: Double = 50_000
    static let floorChoices: [Double] = [20_000, 50_000, 100_000]

    static var floor: Double {
        let value = UserDefaults.standard.double(forKey: floorKey)
        return floorChoices.contains(value) ? value : defaultFloor
    }

    static let green = Color(nsColor: .systemGreen)

    static func nsGreen(dark: Bool) -> NSColor {
        dark ? NSColor(red: 0.35, green: 0.90, blue: 0.45, alpha: 1)
             : NSColor(red: 0.10, green: 0.62, blue: 0.25, alpha: 1)
    }
}

enum Format {
    /// "1.4 MB/s" or, with `bits`, "11 Mbps". Decimal (1000-based) units.
    /// Kilo is the smallest unit: anything under 1 KB/s reads as "0 KB/s".
    static func rate(_ bytesPerSecond: Double, bits: Bool) -> String {
        let units = bits ? ["Kbps", "Mbps", "Gbps"] : ["KB/s", "MB/s", "GB/s"]
        guard bytesPerSecond >= NetworkMonitor.minimumRate else { return "0 \(units[0])" }
        var value = (bits ? bytesPerSecond * 8 : bytesPerSecond) / 1000
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let number = value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        return "\(number) \(units[index])"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.allowsNonnumericFormatting = false // "0 KB", not "Zero KB"
        return formatter
    }()

    static func bytes(_ count: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(clamping: count))
    }
}
