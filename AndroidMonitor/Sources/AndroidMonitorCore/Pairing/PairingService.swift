import Foundation

public enum PairingError: Error, Equatable {
    case invalidEndpoint
    case invalidCode
    case rejected(String)
}

public struct PairingService: Sendable {
    private let adbURL: URL
    private let runner: any CommandRunning

    public init(adbURL: URL, runner: any CommandRunning = ProcessCommandRunner()) {
        self.adbURL = adbURL
        self.runner = runner
    }

    public func pair(host: String, port: Int, code: String) async throws {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...65_535).contains(port) else { throw PairingError.invalidEndpoint }
        guard !code.isEmpty, code.allSatisfy(\.isNumber) else { throw PairingError.invalidCode }
        let result = try await runner.run(CommandRequest(
            executable: adbURL,
            arguments: ["pair", "\(host):\(port)"],
            stdin: Data("\(code)\n".utf8),
            timeout: .seconds(20)
        ))
        let output = String(decoding: result.stdout, as: UTF8.self)
        guard output.localizedCaseInsensitiveContains("successfully paired") else {
            throw PairingError.rejected(String(decoding: result.stderr, as: UTF8.self))
        }
    }

    public func connect(host: String, port: Int) async throws {
        guard !host.isEmpty, (1...65_535).contains(port) else { throw PairingError.invalidEndpoint }
        _ = try await runner.run(CommandRequest(
            executable: adbURL,
            arguments: ["connect", "\(host):\(port)"],
            timeout: .seconds(20)
        ))
    }
}
