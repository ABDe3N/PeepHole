import XCTest
@testable import PeepHole

final class NettopParseTests: XCTestCase {
    func testParsesProcessLines() {
        let output = """
        ,bytes_in,bytes_out,
        Google Chrome H.1410,7229879,284522,
        mDNSResponder.634,25618054,21066797,
        """
        let samples = NettopReader.parse(output)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].name, "Google Chrome H")
        XCTAssertEqual(samples[0].pid, 1410)
        XCTAssertEqual(samples[0].bytesIn, 7_229_879)
        XCTAssertEqual(samples[0].bytesOut, 284_522)
        XCTAssertEqual(samples[1].name, "mDNSResponder")
    }

    func testNamesMayContainDotsAndCommas() {
        let samples = NettopReader.parse("com.apple.Web, Content.812,10,20,\n2.1.269.12611,5,6,")
        XCTAssertEqual(samples.map(\.name), ["com.apple.Web, Content", "2.1.269"])
        XCTAssertEqual(samples.map(\.pid), [812, 12611])
    }

    func testSkipsMalformedLines() {
        let output = """
        ,bytes_in,bytes_out,
        no-pid-here,1,2,
        name.12,not-a-number,2,
        short.5,1,

        ok.7,1,2,
        """
        XCTAssertEqual(NettopReader.parse(output).map(\.pid), [7])
    }
}

final class FormatTests: XCTestCase {
    func testRates() {
        XCTAssertEqual(Format.rate(0, bits: false), "0 KB/s")
        XCTAssertEqual(Format.rate(999, bits: false), "0 KB/s")
        XCTAssertEqual(Format.rate(1_500, bits: false), "1.5 KB/s")
        XCTAssertEqual(Format.rate(250_000, bits: false), "250 KB/s")
        XCTAssertEqual(Format.rate(1_400_000, bits: false), "1.4 MB/s")
        XCTAssertEqual(Format.rate(1_400_000, bits: true), "11 Mbps")
        XCTAssertEqual(Format.rate(5_000_000_000_000, bits: false), "5000 GB/s")
    }
}

@MainActor
final class ProcessResolverTests: XCTestCase {
    func testOutermostAppBundle() {
        XCTAssertEqual(
            ProcessResolver.outermostAppBundle(
                in: "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"),
            "/Applications/Google Chrome.app")
        XCTAssertNil(ProcessResolver.outermostAppBundle(in: "/usr/bin/curl"))
    }

    func testTemporaryLocations() {
        XCTAssertTrue(AppLocation.isTemporary(path: "/Volumes/PeepHole 1.0/PeepHole.app"))
        XCTAssertTrue(AppLocation.isTemporary(
            path: "/private/var/folders/x/AppTranslocation/1234/d/PeepHole.app"))
        XCTAssertFalse(AppLocation.isTemporary(path: "/Applications/PeepHole.app"))
        XCTAssertFalse(AppLocation.isTemporary(path: "/Users/me/Applications/PeepHole.app"))
    }
}

@MainActor
final class NetworkMonitorTests: XCTestCase {
    // PIDs this high don't exist, so identities fall back to the nettop name.
    private let pidA: Int32 = 99_990_001
    private let pidB: Int32 = 99_990_002

    private func sample(_ pid: Int32, _ name: String, _ bytesIn: UInt64) -> ProcessSample {
        ProcessSample(pid: pid, name: name, bytesIn: bytesIn, bytesOut: 0)
    }

    func testRatesFromCounterDeltas() {
        let monitor = NetworkMonitor(sampling: false)
        let start = Date()
        monitor.ingest([sample(pidA, "curl", 1_000)], at: start)
        monitor.ingest([sample(pidA, "curl", 2_001_000)], at: start.addingTimeInterval(2))
        XCTAssertEqual(monitor.totalDownRate, 1_000_000, accuracy: 0.001)
        let rows = monitor.rows(mode: .live, groupByApp: false, sort: .traffic)
        XCTAssertEqual(rows.map(\.pids), [[pidA]])
    }

    func testExitedProcessesMergeAndCannotBeQuit() {
        let monitor = NetworkMonitor(sampling: false)
        let t = Date()
        // Two short-lived processes with the same executable, one after another.
        monitor.ingest([sample(pidA, "curl", 0)], at: t)
        monitor.ingest([sample(pidA, "curl", 3_000_000)], at: t.addingTimeInterval(1))
        monitor.ingest([], at: t.addingTimeInterval(2))
        monitor.ingest([sample(pidB, "curl", 0)], at: t.addingTimeInterval(3))
        monitor.ingest([sample(pidB, "curl", 2_000_000)], at: t.addingTimeInterval(4))
        monitor.ingest([], at: t.addingTimeInterval(5))

        XCTAssertTrue(monitor.entries.isEmpty, "exited processes must not accumulate")
        XCTAssertTrue(monitor.rows(mode: .live, groupByApp: true, sort: .name).isEmpty)

        let session = monitor.rows(mode: .session, groupByApp: false, sort: .name)
        XCTAssertEqual(session.count, 1)
        XCTAssertEqual(session[0].totalDown, 5_000_000)
        XCTAssertEqual(session[0].pids, [], "an exited row must not offer its old PID to Quit")
        XCTAssertTrue(session[0].subtitle.hasPrefix("exited"))
    }

    func testRecycledPIDStartsFresh() {
        let monitor = NetworkMonitor(sampling: false)
        let t = Date()
        monitor.ingest([sample(pidA, "curl", 5_000_000)], at: t)
        // Same PID, different process: the old counter must not produce a delta.
        monitor.ingest([sample(pidA, "wget", 5_000_100)], at: t.addingTimeInterval(1))
        XCTAssertEqual(monitor.totalDownRate, 0)
        XCTAssertEqual(monitor.entries[pidA]?.rawName, "wget")
    }
}
