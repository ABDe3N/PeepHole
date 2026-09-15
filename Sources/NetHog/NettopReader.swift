import Foundation

/// One line of `nettop -P` output: cumulative bytes for a single process.
struct ProcessSample {
    let pid: Int32
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
}

/// Reads per-process network counters using the built-in `/usr/bin/nettop`.
/// nettop needs no root privileges and sees every process on the system.
enum NettopReader {
    static func sample() -> [ProcessSample] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -P: one summary line per process, -L 1: a single CSV sample,
        // -t external: skip loopback traffic, -x: raw byte counts.
        process.arguments = ["-P", "-L", "1", "-t", "external", "-J", "bytes_in,bytes_out", "-x"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Parses lines shaped like `Google Chrome H.1410,7229879,284522,`.
    /// Process names may contain dots or commas, so parse from the right.
    static func parse(_ text: String) -> [ProcessSample] {
        var result: [ProcessSample] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = Substring(rawLine)
            if line.hasSuffix(",") { line = line.dropLast() }
            if line.hasPrefix(",") { continue } // header row

            var fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3,
                  let bytesOut = UInt64(fields.removeLast()),
                  let bytesIn = UInt64(fields.removeLast()) else { continue }

            let namePid = fields.joined(separator: ",")
            guard let dot = namePid.lastIndex(of: "."),
                  let pid = Int32(namePid[namePid.index(after: dot)...]) else { continue }

            result.append(ProcessSample(pid: pid,
                                        name: String(namePid[..<dot]),
                                        bytesIn: bytesIn,
                                        bytesOut: bytesOut))
        }
        return result
    }
}
