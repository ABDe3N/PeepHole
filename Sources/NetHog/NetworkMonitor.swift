import AppKit
import Combine

/// A row shown in the popover: either a whole app or a single process.
struct UsageRow: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: NSImage?
    let pids: [Int32]         // running processes only, so Quit never hits a recycled PID
    let executablePath: String?
    let appBundlePath: String?
    let appName: String
    let downRate: Double      // bytes per second
    let upRate: Double
    let averageRate: Double   // smoothed over a few seconds, used for sorting
    let totalDown: UInt64     // bytes since NetHog started
    let totalUp: UInt64
    let lastActive: Date
    let children: [UsageRow]

    var rate: Double { downRate + upRate }
    var total: UInt64 { totalDown + totalUp }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case name = "Name"
    case traffic = "Traffic"
    var id: String { rawValue }
}

struct ThroughputPoint: Identifiable {
    let id: Int
    let down: Double
    let up: Double
}

enum ViewMode: String, CaseIterable, Identifiable {
    case live = "Live"
    case session = "Since Launch"
    var id: String { rawValue }
}

@MainActor
final class NetworkMonitor: ObservableObject {
    /// How long a process stays listed in Live mode after its traffic stops.
    static let lingerSeconds: TimeInterval = 5
    static let historyLength = 60
    /// Smallest rate worth printing; anything lower reads as "0 KB/s".
    /// (Which apps get a row at all is decided by `Activity.floor`.)
    nonisolated static let minimumRate: Double = 1000

    @Published private(set) var totalDownRate: Double = 0
    @Published private(set) var totalUpRate: Double = 0
    @Published private(set) var history: [ThroughputPoint] = []
    @Published private(set) var entries: [Int32: ProcessEntry] = [:]
    /// Exited processes, merged per executable so memory and per-tick work stay
    /// bounded no matter how long NetHog runs. Only shown in Since Launch.
    private var retired: [String: ProcessEntry] = [:]
    /// Fires after every sample, once all published values are updated.
    let didUpdate = PassthroughSubject<Void, Never>()

    struct ProcessEntry {
        let pid: Int32
        let rawName: String
        let identity: ProcessIdentity
        var lastBytesIn: UInt64?
        var lastBytesOut: UInt64?
        var downRate: Double = 0
        var upRate: Double = 0
        var averageRate: Double = 0
        var totalDown: UInt64 = 0
        var totalUp: UInt64 = 0
        var lastActive: Date = .distantPast
        var wasAboveFloor = false
        var alive = true
    }

    private let resolver = ProcessResolver()
    private var lastSampleTime: Date?
    private var historyCounter = 0
    private var task: Task<Void, Never>?

    init() {
        history = (0..<Self.historyLength).map { ThroughputPoint(id: $0 - Self.historyLength, down: 0, up: 0) }
        start()
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let started = Date()
                let samples = await Task.detached(priority: .utility) { NettopReader.sample() }.value
                self?.ingest(samples, at: Date())
                // Keep a steady ~1 second cadence regardless of how long nettop took.
                let remaining = max(0.2, 1.0 - Date().timeIntervalSince(started))
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
    }

    private func ingest(_ samples: [ProcessSample], at now: Date) {
        let elapsed = lastSampleTime.map { now.timeIntervalSince($0) } ?? 0
        lastSampleTime = now

        var updated = entries
        var seen = Set<Int32>()
        var sumDown: Double = 0
        var sumUp: Double = 0
        let floor = Activity.floor

        for sample in samples {
            seen.insert(sample.pid)
            var entry: ProcessEntry
            if let existing = updated[sample.pid], existing.rawName == sample.name {
                entry = existing
            } else {
                // New process (or a recycled PID): start a fresh entry.
                entry = ProcessEntry(pid: sample.pid, rawName: sample.name,
                                     identity: resolver.resolve(pid: sample.pid, fallbackName: sample.name))
            }

            if let lastIn = entry.lastBytesIn, let lastOut = entry.lastBytesOut, elapsed > 0 {
                // Counters can drop when sockets close; treat that as no traffic.
                let deltaIn = sample.bytesIn >= lastIn ? sample.bytesIn - lastIn : 0
                let deltaOut = sample.bytesOut >= lastOut ? sample.bytesOut - lastOut : 0
                entry.downRate = Double(deltaIn) / elapsed
                entry.upRate = Double(deltaOut) / elapsed
                entry.totalDown += deltaIn
                entry.totalUp += deltaOut
                // Only sustained traffic counts: above the floor for two samples
                // in a row, or a burst big enough that it can't be chatter.
                let rate = entry.downRate + entry.upRate
                let aboveFloor = rate >= floor
                if (aboveFloor && entry.wasAboveFloor) || rate >= floor * 10 { entry.lastActive = now }
                entry.wasAboveFloor = aboveFloor
            } else {
                entry.downRate = 0
                entry.upRate = 0
            }
            // Roughly a 5 second moving average, so sorting by traffic stays calm.
            entry.averageRate = entry.averageRate * 0.8 + (entry.downRate + entry.upRate) * 0.2
            entry.lastBytesIn = sample.bytesIn
            entry.lastBytesOut = sample.bytesOut
            entry.alive = true
            sumDown += entry.downRate
            sumUp += entry.upRate
            updated[sample.pid] = entry
        }

        for (pid, entry) in updated where !seen.contains(pid) {
            updated[pid] = nil
            guard entry.total > 0 else { continue } // never used the network while we watched
            let key = entry.identity.groupKey + "|" + entry.identity.name
            if var existing = retired[key] {
                existing.totalDown += entry.totalDown
                existing.totalUp += entry.totalUp
                existing.lastActive = max(existing.lastActive, entry.lastActive)
                retired[key] = existing
            } else {
                var dead = entry
                dead.alive = false
                dead.downRate = 0
                dead.upRate = 0
                dead.averageRate = 0
                dead.lastBytesIn = nil
                dead.lastBytesOut = nil
                retired[key] = dead
            }
        }

        entries = updated
        totalDownRate = sumDown
        totalUpRate = sumUp

        historyCounter += 1
        history.append(ThroughputPoint(id: historyCounter, down: sumDown, up: sumUp))
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
        didUpdate.send()
    }

    // MARK: - Rows for display

    func rows(mode: ViewMode, groupByApp: Bool, sort: SortOrder) -> [UsageRow] {
        let order = sorter(mode, sort)
        let now = Date()
        let pool = mode == .session ? Array(entries.values) + Array(retired.values) : Array(entries.values)
        let relevant = pool.filter { entry in
            switch mode {
            case .live: return entry.alive && now.timeIntervalSince(entry.lastActive) <= Self.lingerSeconds
            // Was a real user at some point, or trickled a lot over time.
            case .session: return entry.lastActive != .distantPast || entry.total >= 1_000_000
            }
        }

        let rows: [UsageRow]
        if groupByApp {
            let grouped = Dictionary(grouping: relevant, by: { $0.identity.groupKey })
            rows = grouped.map { key, members in
                let children = members.map(processRow).sorted(by: order)
                let first = members[0].identity
                let count = members.count
                return UsageRow(
                    id: key,
                    name: first.groupName,
                    subtitle: count == 1 ? subtitle(for: members[0], showing: members[0].identity.name)
                                         : "\(count) processes",
                    icon: first.appBundlePath.map(resolver.icon(forBundle:)),
                    pids: members.filter(\.alive).map(\.pid),
                    executablePath: first.executablePath,
                    appBundlePath: first.appBundlePath,
                    appName: first.groupName,
                    downRate: members.reduce(0) { $0 + $1.downRate },
                    upRate: members.reduce(0) { $0 + $1.upRate },
                    averageRate: members.reduce(0) { $0 + $1.averageRate },
                    totalDown: members.reduce(0) { $0 + $1.totalDown },
                    totalUp: members.reduce(0) { $0 + $1.totalUp },
                    lastActive: members.map(\.lastActive).max() ?? .distantPast,
                    children: count > 1 ? children : []
                )
            }
        } else {
            rows = relevant.map(processRow)
        }
        return rows.sorted(by: order)
    }

    private func processRow(_ entry: ProcessEntry) -> UsageRow {
        UsageRow(
            id: entry.alive ? "pid:\(entry.pid):\(entry.rawName)"
                            : "exited:\(entry.identity.groupKey)|\(entry.identity.name)",
            name: entry.identity.name,
            subtitle: subtitle(for: entry, showing: entry.identity.groupName),
            icon: entry.identity.appBundlePath.map(resolver.icon(forBundle:)),
            pids: entry.alive ? [entry.pid] : [],
            executablePath: entry.identity.executablePath,
            appBundlePath: entry.identity.appBundlePath,
            appName: entry.identity.groupName,
            downRate: entry.downRate,
            upRate: entry.upRate,
            averageRate: entry.averageRate,
            totalDown: entry.totalDown,
            totalUp: entry.totalUp,
            lastActive: entry.lastActive,
            children: []
        )
    }

    /// "PID 123 · <detail>" ("exited · <detail>" once gone), where detail is the process
    /// name under an app row, or the owning app under a process row. Omitted when it adds nothing.
    private func subtitle(for entry: ProcessEntry, showing detail: String) -> String {
        var parts = [entry.alive ? "PID \(entry.pid)" : "exited"]
        if entry.identity.groupName != entry.identity.name { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    private func sorter(_ mode: ViewMode, _ sort: SortOrder) -> (UsageRow, UsageRow) -> Bool {
        { a, b in
            if sort == .traffic {
                switch mode {
                case .live:
                    if a.averageRate != b.averageRate { return a.averageRate > b.averageRate }
                case .session:
                    if a.total != b.total { return a.total > b.total }
                }
            }
            let byName = a.name.localizedCaseInsensitiveCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.id < b.id // keeps same-named processes in a fixed order
        }
    }

    // MARK: - Actions

    func quit(_ row: UsageRow) {
        if let bundle = row.appBundlePath {
            // Ask the owning app to quit normally (it can prompt to save).
            let url = URL(fileURLWithPath: bundle).standardizedFileURL
            let owners = NSWorkspace.shared.runningApplications.filter {
                $0.bundleURL?.standardizedFileURL == url
            }
            if !owners.isEmpty {
                owners.forEach { $0.terminate() }
                return
            }
        }
        row.pids.forEach { kill($0, SIGTERM) }
    }

    func revealInFinder(_ row: UsageRow) {
        if let bundle = row.appBundlePath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bundle)])
        } else if let path = row.executablePath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }
}

private extension NetworkMonitor.ProcessEntry {
    var total: UInt64 { totalDown + totalUp }
}
