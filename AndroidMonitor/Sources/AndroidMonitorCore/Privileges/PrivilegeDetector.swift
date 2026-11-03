import Foundation

public enum PrivilegeError: Error, Equatable {
    case invalidPackageIdentifier
}

public actor PrivilegeDetector {
    private let adb: any ADBServing
    private let serial: String
    private var rootGranted: Bool?
    private var debuggablePackages: Set<String> = []

    public init(adb: any ADBServing, serial: String) {
        self.adb = adb
        self.serial = serial
    }

    public func detectRoot() async throws -> Bool {
        if let rootGranted { return rootGranted }
        do {
            let result = try await adb.run(serial: serial, arguments: ["shell", "su", "-c", "id"], timeout: .seconds(5))
            let granted = String(decoding: result.stdout, as: UTF8.self).contains("uid=0")
            if granted { rootGranted = true }
            return granted
        } catch {
            return false
        }
    }

    public func canRunAs(package: String) async throws -> Bool {
        guard Self.isValidPackage(package) else { throw PrivilegeError.invalidPackageIdentifier }
        if debuggablePackages.contains(package) { return true }
        do {
            _ = try await adb.run(
                serial: serial,
                arguments: ["shell", "run-as", package, "id"],
                timeout: .seconds(5)
            )
            debuggablePackages.insert(package)
            return true
        } catch {
            return false
        }
    }

    private static func isValidPackage(_ value: String) -> Bool {
        guard value.contains("."), let first = value.first, first.isLetter else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
    }
}
