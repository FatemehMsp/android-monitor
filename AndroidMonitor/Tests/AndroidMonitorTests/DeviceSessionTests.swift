import Foundation
import XCTest
@testable import AndroidMonitorCore

@MainActor
final class DeviceSessionTests: XCTestCase {
    func testSelectingSecondDeviceClosesFirstSession() async {
        let factory = SessionFactorySpy()
        let model = AppModel(sessionFactory: { serial in factory.make(serial: serial) })

        await model.select(serial: "A")
        await model.select(serial: "B")

        let closed = await factory.closedSerials()
        XCTAssertEqual(closed, ["A"])
        XCTAssertEqual(model.activeSession?.serial, "B")
    }

    func testUnauthorizedDeviceCannotBeSelected() async {
        let model = AppModel(sessionFactory: { ActiveDeviceSession(serial: $0) })
        await model.select(AndroidDevice(serial: "A", state: .unauthorized))
        XCTAssertNil(model.activeSession)
    }
}

private actor SessionFactorySpy {
    private var closed: [String] = []

    nonisolated func make(serial: String) -> ActiveDeviceSession {
        ActiveDeviceSession(serial: serial) { [weak self] serial in
            await self?.recordClosed(serial)
        }
    }

    func recordClosed(_ serial: String) { closed.append(serial) }
    func closedSerials() -> [String] { closed }
}

