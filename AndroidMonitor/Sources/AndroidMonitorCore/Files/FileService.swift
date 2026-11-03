import Foundation

public enum RemoteFileParser {
    public static func paths(_ data: Data) -> [RemoteFile] {
        data.split(separator: 0).compactMap { bytes in
            let path = String(decoding: bytes, as: UTF8.self)
            guard !path.isEmpty else { return nil }
            return RemoteFile(
                path: path,
                name: URL(fileURLWithPath: path).lastPathComponent,
                kind: .file
            )
        }
    }
}

public struct FileService: Sendable {
    private let adb: any ADBServing
    private let serial: String

    public init(adb: any ADBServing, serial: String) {
        self.adb = adb
        self.serial = serial
    }

    public func list(_ path: String) async throws -> [RemoteFile] {
        let resolvedPath = path == "/sdcard" ? "/storage/emulated/0" : path
        let command = "find \(RemoteShell.quote(resolvedPath)) -mindepth 1 -maxdepth 1 -print0"
        let result = try await adb.run(serial: serial, arguments: ["exec-out", "sh", "-c", command], timeout: .seconds(20))
        return RemoteFileParser.paths(result.stdout)
    }

    public func createDirectory(_ path: String) async throws {
        _ = try await adb.run(serial: serial, arguments: ["shell", "mkdir", "-p", "--", RemoteShell.quote(path)], timeout: .seconds(20))
    }

    public func remove(_ path: String) async throws {
        _ = try await adb.run(serial: serial, arguments: ["shell", "rm", "-rf", "--", RemoteShell.quote(path)], timeout: .seconds(30))
    }

    public func move(from: String, to: String) async throws {
        _ = try await adb.run(serial: serial, arguments: ["shell", "mv", "--", RemoteShell.quote(from), RemoteShell.quote(to)], timeout: .seconds(30))
    }

    public func pull(remote: String, local: URL) async throws {
        _ = try await adb.run(serial: serial, arguments: ["pull", remote, local.path], timeout: .seconds(3_600))
    }

    public func push(local: URL, remote: String) async throws {
        _ = try await adb.run(serial: serial, arguments: ["push", local.path, remote], timeout: .seconds(3_600))
    }
}
