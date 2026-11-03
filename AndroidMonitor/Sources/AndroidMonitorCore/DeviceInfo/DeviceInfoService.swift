import Foundation

public struct DeviceInfo: Sendable, Equatable {
    public var manufacturer: String?
    public var model: String?
    public var androidVersion: String?
    public var apiLevel: String?
    public var abi: String?
    public var properties: [String: String]
}

public enum DeviceInfoParser {
    public static func properties(_ text: String) -> DeviceInfo {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \Character.isNewline) {
            guard let separator = line.range(of: "]: [") else { continue }
            let key = String(line.dropFirst().prefix(upTo: separator.lowerBound))
            let valueStart = separator.upperBound
            let value = String(line[valueStart...].dropLast())
            values[key] = value
        }
        return DeviceInfo(
            manufacturer: values["ro.product.manufacturer"],
            model: values["ro.product.model"],
            androidVersion: values["ro.build.version.release"],
            apiLevel: values["ro.build.version.sdk"],
            abi: values["ro.product.cpu.abi"],
            properties: values
        )
    }
}

public struct DeviceInfoService: Sendable {
    private let adb: any ADBServing
    private let serial: String
    public init(adb: any ADBServing, serial: String) { self.adb = adb; self.serial = serial }
    public func load() async throws -> DeviceInfo {
        let result = try await adb.run(serial: serial, arguments: ["shell", "getprop"], timeout: .seconds(15))
        return DeviceInfoParser.properties(String(decoding: result.stdout, as: UTF8.self))
    }
}
