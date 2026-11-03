import Foundation

public struct CommandRequest: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public var stdin: Data?
    public var timeout: Duration

    public init(executable: URL, arguments: [String], stdin: Data? = nil, timeout: Duration = .seconds(30)) {
        self.executable = executable
        self.arguments = arguments
        self.stdin = stdin
        self.timeout = timeout
    }
}

public struct CommandResult: Sendable, Equatable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32

    public init(stdout: Data, stderr: Data, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public enum CommandError: Error, Equatable {
    case launchFailed(String)
    case timedOut
    case cancelled
    case nonZeroExit(code: Int32, stderr: String)
}

public protocol CommandRunning: Sendable {
    func run(_ request: CommandRequest) async throws -> CommandResult
    func stream(_ request: CommandRequest) -> AsyncThrowingStream<Data, Error>
}

