import Foundation

public enum DeviceState: String, Sendable, Equatable {
    case device
    case unauthorized
    case offline
}

public struct AndroidDevice: Identifiable, Sendable, Equatable {
    public let serial: String
    public let state: DeviceState
    public var product: String?
    public var model: String?
    public var transportID: String?
    public var id: String { serial }

    public init(serial: String, state: DeviceState, product: String? = nil, model: String? = nil, transportID: String? = nil) {
        self.serial = serial
        self.state = state
        self.product = product
        self.model = model
        self.transportID = transportID
    }
}

public enum ADBParseError: Error, Equatable {
    case malformedLine(String)
    case unsupportedState(String)
}

