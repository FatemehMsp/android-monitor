import Foundation

public enum AccessLevel: Sendable, Equatable {
    case normal
    case debuggable(package: String)
    case root
}

public struct RemoteFile: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case file, directory, symbolicLink }
    public let path: String
    public let name: String
    public let kind: Kind
    public let size: Int64?
    public let modifiedAt: Date?
    public var id: String { path }

    public init(path: String, name: String, kind: Kind, size: Int64? = nil, modifiedAt: Date? = nil) {
        self.path = path
        self.name = name
        self.kind = kind
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public protocol DataAccessProviding: Sendable {
    var level: AccessLevel { get }
    func list(_ path: String) async throws -> [RemoteFile]
    func read(_ path: String) -> AsyncThrowingStream<Data, Error>
    func write(_ data: AsyncThrowingStream<Data, Error>, to path: String) async throws
    func remove(_ path: String) async throws
    func move(from: String, to: String) async throws
}

public struct PrivilegedOperation: Identifiable, Sendable, Equatable {
    public enum Effect: String, Sendable { case overwrite, delete, clearData, uninstall }
    public let id: UUID
    public let deviceSerial: String
    public let target: String
    public let accessLevel: AccessLevel
    public let effect: Effect

    public init(id: UUID = UUID(), deviceSerial: String, target: String, accessLevel: AccessLevel, effect: Effect) {
        self.id = id
        self.deviceSerial = deviceSerial
        self.target = target
        self.accessLevel = accessLevel
        self.effect = effect
    }
}

