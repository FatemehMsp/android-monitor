import Foundation

public enum LogPriority: String, Sendable, Equatable { case verbose = "V", debug = "D", info = "I", warning = "W", error = "E", fatal = "F" }

public struct LogcatEntry: Sendable, Equatable {
    public let timestamp: TimeInterval
    public let pid: Int
    public let tid: Int
    public let priority: LogPriority
    public let tag: String
    public let message: String
}

public enum LogcatParser {
    public static func entry(_ line: String) -> LogcatEntry? {
        let pattern = #"^(\d+\.\d+)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+([^:]+):\s?(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 7 else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: line).map { String(line[$0]) }
        }
        guard let timestamp = group(1).flatMap(Double.init),
              let pid = group(2).flatMap(Int.init),
              let tid = group(3).flatMap(Int.init),
              let priority = group(4).flatMap(LogPriority.init(rawValue:)),
              let tag = group(5), let message = group(6) else { return nil }
        return LogcatEntry(timestamp: timestamp, pid: pid, tid: tid, priority: priority, tag: tag.trimmingCharacters(in: .whitespaces), message: message)
    }
}

public struct LogcatService: Sendable {
    private let adb: any ADBServing
    private let serial: String
    public init(adb: any ADBServing, serial: String) { self.adb = adb; self.serial = serial }
    /// `recentLines` limits the initial backlog so reopening the stream does not replay the whole device buffer.
    public func stream(recentLines: Int = 500) -> AsyncThrowingStream<Data, Error> {
        adb.stream(serial: serial, arguments: ["logcat", "-v", "epoch", "-T", String(recentLines)])
    }
    public func clear() async throws {
        _ = try await adb.run(serial: serial, arguments: ["logcat", "-c"], timeout: .seconds(10))
    }
}
