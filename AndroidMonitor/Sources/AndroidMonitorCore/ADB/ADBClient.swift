import Foundation

public protocol ADBServing: Sendable {
    func devices() async throws -> [AndroidDevice]
    func trackDevices() -> AsyncThrowingStream<[AndroidDevice], Error>
    func run(serial: String, arguments: [String], timeout: Duration) async throws -> CommandResult
    func stream(serial: String, arguments: [String]) -> AsyncThrowingStream<Data, Error>
}

public struct ADBClient: ADBServing {
    private let adbURL: URL
    private let runner: any CommandRunning

    public init(adbURL: URL, runner: any CommandRunning = ProcessCommandRunner()) {
        self.adbURL = adbURL
        self.runner = runner
    }

    public func devices() async throws -> [AndroidDevice] {
        let result = try await runner.run(CommandRequest(executable: adbURL, arguments: ["devices", "-l"]))
        return try ADBOutputParser.devices(String(decoding: result.stdout, as: UTF8.self))
    }

    public func trackDevices() -> AsyncThrowingStream<[AndroidDevice], Error> {
        let chunks = runner.stream(CommandRequest(executable: adbURL, arguments: ["track-devices", "-l"], timeout: .seconds(86_400)))
        return AsyncThrowingStream { continuation in
            let task = Task {
                var buffer = ""
                do {
                    for try await chunk in chunks {
                        buffer += String(decoding: chunk, as: UTF8.self)
                        while let range = buffer.range(of: "\n\n") {
                            let snapshot = String(buffer[..<range.lowerBound])
                            buffer.removeSubrange(..<range.upperBound)
                            continuation.yield(try ADBOutputParser.devices(snapshot))
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func run(serial: String, arguments: [String], timeout: Duration = .seconds(30)) async throws -> CommandResult {
        try await runner.run(CommandRequest(executable: adbURL, arguments: ["-s", serial] + arguments, timeout: timeout))
    }

    public func stream(serial: String, arguments: [String]) -> AsyncThrowingStream<Data, Error> {
        runner.stream(CommandRequest(executable: adbURL, arguments: ["-s", serial] + arguments, timeout: .seconds(86_400)))
    }
}

