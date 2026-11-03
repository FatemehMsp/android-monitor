import Foundation

public struct ProtectedDataService: Sendable {
    private let adbURL: URL
    private let runner: any CommandRunning
    private let serial: String

    public init(adbURL: URL, runner: any CommandRunning = ProcessCommandRunner(), serial: String) {
        self.adbURL = adbURL; self.runner = runner; self.serial = serial
    }

    public func read(path: String, access: AccessLevel) async throws -> Data {
        let arguments = ["-s", serial, "exec-out"] + command(prefix: "cat -- \(RemoteShell.quote(path))", access: access)
        return try await runner.run(CommandRequest(executable: adbURL, arguments: arguments, timeout: .seconds(60))).stdout
    }

    public func write(_ data: Data, path: String, access: AccessLevel) async throws {
        let original = try await read(path: path, access: access)
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("AndroidMonitor/Backups/\(serial)/\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try original.write(to: root.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent), options: .atomic)
        let temporary = "\(path).androidmonitor-\(UUID().uuidString)"
        let write = ["-s", serial, "exec-in"] + command(prefix: "cat > \(RemoteShell.quote(temporary))", access: access)
        _ = try await runner.run(CommandRequest(executable: adbURL, arguments: write, stdin: data, timeout: .seconds(120)))
        let replace = ["-s", serial, "shell"] + command(prefix: "mv -- \(RemoteShell.quote(temporary)) \(RemoteShell.quote(path))", access: access)
        _ = try await runner.run(CommandRequest(executable: adbURL, arguments: replace, timeout: .seconds(30)))
    }

    public func list(path: String, access: AccessLevel) async throws -> [RemoteFile] {
        let script = "find \(RemoteShell.quote(path)) -mindepth 1 -maxdepth 1 -print0"
        let arguments = ["-s", serial, "exec-out"] + command(prefix: script, access: access)
        let data = try await runner.run(CommandRequest(executable: adbURL, arguments: arguments, timeout: .seconds(30))).stdout
        return RemoteFileParser.paths(data)
    }

    private func command(prefix script: String, access: AccessLevel) -> [String] {
        switch access {
        case .normal: return ["sh", "-c", script]
        case .debuggable(let package): return ["run-as", package, "sh", "-c", script]
        case .root: return ["su", "-c", script]
        }
    }
}

