import Foundation

struct AppTrafficEntry {
    let appName: String
    let downloadBytesPerSec: UInt64
    let uploadBytesPerSec: UInt64
}

private struct TrafficSample {
    let timestamp: Date
    let entries: [String: (bytesIn: UInt64, bytesOut: UInt64)]
}

final class TrafficMonitor {
    var connectionType: ConnectionType = .ethernet
    private var previousSnapshot: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var previousTime: Date?
    private var history: [TrafficSample] = []
    private let historyWindow: TimeInterval = 600 // 10 minutes

    func sample() -> [AppTrafficEntry] {
        let now = Date()
        let snapshot = takeSnapshot()

        defer {
            previousSnapshot = snapshot
            previousTime = now
        }

        guard let prevTime = previousTime else { return [] }
        let elapsed = now.timeIntervalSince(prevTime)
        guard elapsed > 0 else { return [] }

        var entries: [AppTrafficEntry] = []
        for (app, current) in snapshot {
            guard let prev = previousSnapshot[app] else { continue }
            let inDelta = current.bytesIn >= prev.bytesIn
                ? current.bytesIn - prev.bytesIn
                : current.bytesIn
            let outDelta = current.bytesOut >= prev.bytesOut
                ? current.bytesOut - prev.bytesOut
                : current.bytesOut

            let dlPerSec = UInt64(Double(inDelta) / elapsed)
            let ulPerSec = UInt64(Double(outDelta) / elapsed)

            if dlPerSec > 0 || ulPerSec > 0 {
                entries.append(AppTrafficEntry(
                    appName: app,
                    downloadBytesPerSec: dlPerSec,
                    uploadBytesPerSec: ulPerSec
                ))
            }
        }

        entries.sort { ($0.downloadBytesPerSec + $0.uploadBytesPerSec) > ($1.downloadBytesPerSec + $1.uploadBytesPerSec) }
        return Array(entries.prefix(5))
    }

    func sampleAverage() -> [AppTrafficEntry] {
        let now = Date()
        let snapshot = takeSnapshot()

        // Update instantaneous state too so switching modes stays seamless
        previousSnapshot = snapshot
        previousTime = now

        // Append current snapshot and prune old entries
        history.append(TrafficSample(timestamp: now, entries: snapshot))
        let cutoff = now.addingTimeInterval(-historyWindow)
        history.removeAll { $0.timestamp < cutoff }

        guard history.count >= 2,
              let oldest = history.first,
              let newest = history.last else {
            return []
        }

        let elapsed = newest.timestamp.timeIntervalSince(oldest.timestamp)
        guard elapsed > 0 else { return [] }

        // Compute average bytes/sec per app over the window
        var entries: [AppTrafficEntry] = []
        for (app, current) in newest.entries {
            guard let prev = oldest.entries[app] else { continue }
            let inDelta = current.bytesIn >= prev.bytesIn
                ? current.bytesIn - prev.bytesIn
                : current.bytesIn
            let outDelta = current.bytesOut >= prev.bytesOut
                ? current.bytesOut - prev.bytesOut
                : current.bytesOut

            let dlPerSec = UInt64(Double(inDelta) / elapsed)
            let ulPerSec = UInt64(Double(outDelta) / elapsed)

            if dlPerSec > 0 || ulPerSec > 0 {
                entries.append(AppTrafficEntry(
                    appName: app,
                    downloadBytesPerSec: dlPerSec,
                    uploadBytesPerSec: ulPerSec
                ))
            }
        }

        entries.sort { ($0.downloadBytesPerSec + $0.uploadBytesPerSec) > ($1.downloadBytesPerSec + $1.uploadBytesPerSec) }
        return Array(entries.prefix(5))
    }

    func reset() {
        previousSnapshot = [:]
        previousTime = nil
        history = []
    }

    // MARK: - nettop

    private func takeSnapshot() -> [String: (bytesIn: UInt64, bytesOut: UInt64)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out", "-t", connectionType.nettopFilter]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return [:]
        }

        return parseCSV(output)
    }

    private func parseCSV(_ output: String) -> [String: (bytesIn: UInt64, bytesOut: UInt64)] {
        let lines = output.components(separatedBy: "\n")
        guard lines.count > 1 else { return [:] }

        // Find column indices from header
        let header = lines[0].components(separatedBy: ",")
        guard let bytesInIdx = header.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "bytes_in" }),
              let bytesOutIdx = header.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "bytes_out" }) else {
            return [:]
        }

        var result: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: ",")
            guard cols.count > max(bytesInIdx, bytesOutIdx),
                  !cols[0].isEmpty else { continue }

            let processField = cols[0].trimmingCharacters(in: .whitespaces)
            let appName = extractAppName(from: processField)

            let bytesIn = UInt64(cols[bytesInIdx].trimmingCharacters(in: .whitespaces)) ?? 0
            let bytesOut = UInt64(cols[bytesOutIdx].trimmingCharacters(in: .whitespaces)) ?? 0

            // Aggregate multiple PIDs for the same app
            if let existing = result[appName] {
                result[appName] = (bytesIn: existing.bytesIn + bytesIn, bytesOut: existing.bytesOut + bytesOut)
            } else {
                result[appName] = (bytesIn: bytesIn, bytesOut: bytesOut)
            }
        }

        return result
    }

    private func extractAppName(from processField: String) -> String {
        // nettop outputs "ProcessName.PID" — strip the .PID suffix
        if let dotRange = processField.range(of: ".", options: .backwards),
           let _ = Int(processField[dotRange.upperBound...]) {
            return String(processField[..<dotRange.lowerBound])
        }
        return processField
    }
}
