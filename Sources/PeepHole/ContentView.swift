import Charts
import ServiceManagement
import SwiftUI

private let downColor = Color(red: 0.20, green: 0.55, blue: 1.0)
private let upColor = Color(red: 1.0, green: 0.45, blue: 0.20)

struct ContentView: View {
    @ObservedObject var monitor: NetworkMonitor
    @AppStorage("viewMode") private var mode: ViewMode = .live
    @AppStorage("groupByApp") private var groupByApp = true
    @AppStorage("useBits") private var useBits = false
    @AppStorage("sortOrder") private var sort: SortOrder = .name
    @AppStorage(Activity.thresholdKey) private var threshold = Activity.defaultThreshold
    @State private var expanded: Set<String> = []

    var body: some View {
        let rows = monitor.rows(mode: mode, groupByApp: groupByApp, sort: sort)
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            list(rows)
            Divider()
            FooterView(monitor: monitor)
        }
        .frame(width: 400)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("PeepHole").font(.system(size: 13, weight: .bold))
                Spacer()
                Text("All apps, excluding localhost")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                speedTile(title: "Download", symbol: "arrow.down", value: monitor.totalDownRate, color: downColor)
                speedTile(title: "Upload", symbol: "arrow.up", value: monitor.totalUpRate, color: upColor)
                Spacer()
            }
            ThroughputChart(history: monitor.history)
                .frame(height: 44)
        }
        .padding(12)
    }

    private func speedTile(title: String, symbol: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ActivityArrow(symbol: symbol, active: value >= threshold)
                Text(title).foregroundStyle(color)
            }
            .font(.system(size: 10, weight: .medium))
            Text(Format.rate(value, bits: useBits))
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack {
            Picker("", selection: $mode) {
                ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            Spacer()
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(sort == .name ? "Sorted by name" : "Sorted by traffic (5 second average)")
            Toggle(isOn: $groupByApp) {
                Label("Group", systemImage: "square.stack.3d.up")
                    .font(.system(size: 11))
            }
            .toggleStyle(.button)
            .help("Merge helper processes into their app")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: List

    @ViewBuilder
    private func list(_ rows: [UsageRow]) -> some View {
        if rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: mode == .live ? "wifi" : "clock")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text(mode == .live ? "No app is above \(Format.rate(Activity.floor, bits: useBits)) right now"
                                   : "No traffic recorded yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 340)
        } else {
            let peak = rows.map { mode == .live ? $0.rate : Double($0.total) }.max() ?? 0
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        RowView(row: row, mode: mode, useBits: useBits, peak: peak, threshold: threshold,
                                isExpanded: expanded.contains(row.id),
                                toggleExpanded: { toggle(row.id) },
                                monitor: monitor)
                        if expanded.contains(row.id) {
                            ForEach(row.children) { child in
                                RowView(row: child, mode: mode, useBits: useBits, peak: peak, threshold: threshold,
                                        isChild: true, monitor: monitor)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 340)
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

// MARK: - Chart

struct ThroughputChart: View {
    let history: [ThroughputPoint]

    var body: some View {
        Chart {
            ForEach(history) { point in
                AreaMark(x: .value("Time", point.id), y: .value("Download", point.down),
                         series: .value("Direction", "Download"), stacking: .unstacked)
                    .foregroundStyle(LinearGradient(colors: [downColor.opacity(0.45), downColor.opacity(0.05)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.id), y: .value("Download", point.down),
                         series: .value("Direction", "DownloadLine"))
                    .foregroundStyle(downColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.id), y: .value("Upload", point.up),
                         series: .value("Direction", "Upload"))
                    .foregroundStyle(upColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...max(1, history.map { max($0.down, $0.up) }.max() ?? 1))
    }
}

// MARK: - Row

struct RowView: View {
    let row: UsageRow
    let mode: ViewMode
    let useBits: Bool
    let peak: Double
    let threshold: Double
    var isChild = false
    var isExpanded = false
    var toggleExpanded: (() -> Void)?
    let monitor: NetworkMonitor

    @State private var hovering = false

    private var isIdle: Bool { mode == .live && row.rate < Activity.floor }
    private var isBusy: Bool { row.downRate >= threshold || row.upRate >= threshold }
    private var share: Double {
        guard peak > 0 else { return 0 }
        let value = (mode == .live ? row.rate : Double(row.total)) / peak
        return value < 0.02 ? 0 : value // skip slivers too thin to read
    }

    var body: some View {
        HStack(spacing: 8) {
            disclosure
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: isChild ? 11 : 12, weight: isChild ? .regular : .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // Upload on top, download below — same layout as the menu bar readout.
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 3) {
                    Text(mode == .live ? Format.rate(row.upRate, bits: useBits) : Format.bytes(row.totalUp))
                    ActivityArrow(symbol: "arrow.up", active: row.upRate >= threshold)
                }
                HStack(spacing: 3) {
                    Text(mode == .live ? Format.rate(row.downRate, bits: useBits) : Format.bytes(row.totalDown))
                    ActivityArrow(symbol: "arrow.down", active: row.downRate >= threshold)
                }
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.leading, isChild ? 26 : 8)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .opacity(isIdle ? 0.5 : 1)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 5)
                    .fill(isBusy ? Activity.green.opacity(isChild ? 0.08 : 0.16)
                                 : Color.primary.opacity(isChild ? 0.04 : 0.07))
                    .frame(width: geo.size.width * share)
                    .animation(.easeOut(duration: 0.4), value: share)
            }
        }
        .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.primary.opacity(0.06) : .clear))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { toggleExpanded?() }
        .contextMenu {
            if !row.pids.isEmpty {
                Button("Quit \(row.appBundlePath != nil ? row.appName : row.name)") { monitor.quit(row) }
            }
            Button("Show in Finder") { monitor.revealInFinder(row) }
            if row.pids.count == 1, let pid = row.pids.first {
                Button("Copy PID \(pid)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(pid)", forType: .string)
                }
            }
        }
    }

    @ViewBuilder private var disclosure: some View {
        if !row.children.isEmpty {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeOut(duration: 0.15), value: isExpanded)
                .frame(width: 10)
        } else if !isChild {
            Color.clear.frame(width: 10)
        }
    }

    @ViewBuilder private var icon: some View {
        let size: CGFloat = isChild ? 16 : 22
        if let image = row.icon {
            Image(nsImage: image).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: size * 0.55))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
        }
    }
}

/// Arrow that lights up green while that direction is above the activity threshold.
struct ActivityArrow: View {
    let symbol: String
    let active: Bool

    var body: some View {
        Image(systemName: symbol)
            .fontWeight(active ? .heavy : .regular)
            .foregroundStyle(active ? Activity.green : Color.secondary.opacity(0.5))
            .animation(.easeOut(duration: 0.25), value: active)
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var monitor: NetworkMonitor
    @AppStorage("showSpeedsInMenuBar") private var showSpeeds = true
    @AppStorage("useBits") private var useBits = false
    @AppStorage(Activity.thresholdKey) private var threshold = Activity.defaultThreshold
    @AppStorage(Activity.floorKey) private var floor = Activity.defaultFloor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        HStack {
            Menu {
                Toggle("Show speeds in menu bar", isOn: $showSpeeds)
                Toggle("Show speeds in bits (Mbps)", isOn: $useBits)
                Picker("Hide apps below", selection: $floor) {
                    ForEach(Activity.floorChoices, id: \.self) { Text(Format.rate($0, bits: useBits)).tag($0) }
                }
                Picker("Turn arrows green above", selection: $threshold) {
                    ForEach(Activity.choices, id: \.self) { Text(Format.rate($0, bits: useBits)).tag($0) }
                }
                if AppLocation.isTemporary {
                    Text("Move PeepHole to Applications to launch at login")
                } else {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
                if updates.isAvailable {
                    Divider()
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .disabled(!updates.canCheck)
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()
            Text("Right-click a row to quit it")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()

            Button("Quit PeepHole") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
