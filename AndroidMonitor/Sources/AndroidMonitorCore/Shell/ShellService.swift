import Foundation

public struct ShellService: Sendable {
    private let adb: any ADBServing
    private let serial: String
    public init(adb: any ADBServing, serial: String) { self.adb = adb; self.serial = serial }

    public func execute(_ command: String, root: Bool = false) async throws -> String {
        let arguments = root
            ? ["shell", "su", "-c", command]
            : ["shell", "sh", "-c", command]
        let result = try await adb.run(serial: serial, arguments: arguments, timeout: .seconds(120))
        return String(decoding: result.stdout, as: UTF8.self)
    }
}
