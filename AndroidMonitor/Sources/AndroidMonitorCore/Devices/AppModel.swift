import Foundation

@MainActor
public final class AppModel {
    public private(set) var activeSession: ActiveDeviceSession?
    private let sessionFactory: @MainActor (String) -> ActiveDeviceSession

    public init(sessionFactory: @escaping @MainActor (String) -> ActiveDeviceSession = { ActiveDeviceSession(serial: $0) }) {
        self.sessionFactory = sessionFactory
    }

    public func select(_ device: AndroidDevice) async {
        guard device.state == .device else { return }
        await select(serial: device.serial)
    }

    public func select(serial: String) async {
        guard activeSession?.serial != serial else { return }
        await activeSession?.close()
        activeSession = sessionFactory(serial)
    }

    public func disconnect() async {
        await activeSession?.close()
        activeSession = nil
    }
}
