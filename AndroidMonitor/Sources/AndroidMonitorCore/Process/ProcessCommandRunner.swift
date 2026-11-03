import Foundation

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ request: CommandRequest) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let execution = ProcessExecution(request: request, continuation: continuation)
            execution.start()
        }
    }

    public func stream(_ request: CommandRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let execution = ProcessStreamExecution(request: request, continuation: continuation)
            execution.start()
            continuation.onTermination = { _ in execution.cancel() }
        }
    }
}

private final class ProcessStreamExecution: @unchecked Sendable {
    private let request: CommandRequest
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let process = Process()
    private let output = Pipe()
    private let errors = Pipe()
    private let input = Pipe()

    init(request: CommandRequest, continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        self.request = request
        self.continuation = continuation
    }

    func start() {
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.standardOutput = output
        process.standardError = errors
        if request.stdin != nil { process.standardInput = input }
        output.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            if !data.isEmpty { continuation.yield(data) }
        }
        process.terminationHandler = { [self] process in
            output.fileHandleForReading.readabilityHandler = nil
            if process.terminationStatus == 0 || process.terminationReason == .uncaughtSignal {
                continuation.finish()
            } else {
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.finish(throwing: CommandError.nonZeroExit(code: process.terminationStatus, stderr: message))
            }
        }
        do {
            try process.run()
            if let data = request.stdin {
                try input.fileHandleForWriting.write(contentsOf: data)
                try input.fileHandleForWriting.close()
            }
        } catch {
            continuation.finish(throwing: CommandError.launchFailed(error.localizedDescription))
        }
    }

    func cancel() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }
}

private final class ProcessExecution: @unchecked Sendable {
    private let request: CommandRequest
    private let process = Process()
    private let output = Pipe()
    private let errors = Pipe()
    private let input = Pipe()
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var continuation: CheckedContinuation<CommandResult, Error>?

    init(request: CommandRequest, continuation: CheckedContinuation<CommandResult, Error>) {
        self.request = request
        self.continuation = continuation
    }

    func start() {
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.standardOutput = output
        process.standardError = errors
        if request.stdin != nil { process.standardInput = input }
        output.fileHandleForReading.readabilityHandler = { [self] handle in
            append(handle.availableData, toStdout: true)
        }
        errors.fileHandleForReading.readabilityHandler = { [self] handle in
            append(handle.availableData, toStdout: false)
        }
        process.terminationHandler = { [self] process in terminated(process.terminationStatus) }
        do {
            try process.run()
            if let data = request.stdin {
                try input.fileHandleForWriting.write(contentsOf: data)
                try input.fileHandleForWriting.close()
            }
        } catch {
            finish(.failure(CommandError.launchFailed(error.localizedDescription)))
            return
        }
        Task.detached { [self, timeout = request.timeout] in
            try? await Task.sleep(for: timeout)
            timeOut()
        }
    }

    private func append(_ data: Data, toStdout: Bool) {
        guard !data.isEmpty else { return }
        lock.withLock {
            if toStdout { stdout.append(data) } else { stderr.append(data) }
        }
    }

    private func terminated(_ code: Int32) {
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        let data = lock.withLock { (stdout, stderr) }
        let result = CommandResult(stdout: data.0, stderr: data.1, exitCode: code)
        if code == 0 {
            finish(.success(result))
        } else {
            finish(.failure(CommandError.nonZeroExit(code: code, stderr: String(decoding: data.1, as: UTF8.self))))
        }
    }

    private func timeOut() {
        finish(.failure(CommandError.timedOut))
        if process.isRunning { process.terminate() }
    }

    private func finish(_ result: Result<CommandResult, Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<CommandResult, Error>? in
            defer { continuation = nil }
            return continuation
        }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        pending?.resume(with: result)
    }
}

