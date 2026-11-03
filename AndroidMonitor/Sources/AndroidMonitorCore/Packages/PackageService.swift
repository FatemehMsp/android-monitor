import Foundation

public struct AndroidPackage: Identifiable, Sendable, Equatable {
    public let identifier: String
    public let apkPath: String?
    public var id: String { identifier }
    public init(identifier: String, apkPath: String? = nil) {
        self.identifier = identifier
        self.apkPath = apkPath
    }
}

public enum PackageOutputParser {
    public static func packages(_ text: String) -> [AndroidPackage] {
        text.split(whereSeparator: \Character.isNewline).compactMap { line in
            let value = line.hasPrefix("package:") ? line.dropFirst(8) : line[...]
            guard let separator = value.lastIndex(of: "=") else { return nil }
            return AndroidPackage(
                identifier: String(value[value.index(after: separator)...]),
                apkPath: String(value[..<separator])
            )
        }
    }
}

public struct PackageService: Sendable {
    private let adb: any ADBServing
    private let serial: String
    public init(adb: any ADBServing, serial: String) { self.adb = adb; self.serial = serial }

    public func packages() async throws -> [AndroidPackage] {
        let result = try await adb.run(serial: serial, arguments: ["shell", "pm", "list", "packages", "-f"], timeout: .seconds(30))
        return PackageOutputParser.packages(String(decoding: result.stdout, as: UTF8.self))
    }

    public func install(_ apk: URL) async throws {
        _ = try await adb.run(serial: serial, arguments: ["install", "-r", apk.path], timeout: .seconds(600))
    }

    public func uninstall(_ package: String) async throws {
        _ = try await adb.run(serial: serial, arguments: ["uninstall", package], timeout: .seconds(60))
    }

    public func launch(_ package: String) async throws {
        _ = try await adb.run(serial: serial, arguments: ["shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1"], timeout: .seconds(30))
    }

    public func forceStop(_ package: String) async throws {
        _ = try await adb.run(serial: serial, arguments: ["shell", "am", "force-stop", package], timeout: .seconds(30))
    }

    public func clearData(_ package: String) async throws {
        _ = try await adb.run(serial: serial, arguments: ["shell", "pm", "clear", package], timeout: .seconds(60))
    }
}
