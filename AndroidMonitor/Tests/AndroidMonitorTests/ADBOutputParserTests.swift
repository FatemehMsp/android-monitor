import Foundation
import XCTest
@testable import AndroidMonitorCore

final class ADBOutputParserTests: XCTestCase {
    func testParsesConnectedAndUnauthorizedDevices() throws {
        let text = """
        List of devices attached
        ABC123 device product:husky model:Pixel_8 transport_id:4
        XYZ unauthorized transport_id:5

        """

        let devices = try ADBOutputParser.devices(text)

        XCTAssertEqual(devices, [
            AndroidDevice(serial: "ABC123", state: .device, product: "husky", model: "Pixel_8", transportID: "4"),
            AndroidDevice(serial: "XYZ", state: .unauthorized, product: nil, model: nil, transportID: "5")
        ])
    }

    func testRejectsUnknownDeviceState() {
        XCTAssertThrowsError(try ADBOutputParser.devices("ABC123 recovery\n"))
    }

    func testSelectedDeviceCommandAlwaysContainsSerial() async throws {
        let runner = FakeCommandRunner(result: CommandResult(stdout: Data(), stderr: Data(), exitCode: 0))
        let client = ADBClient(adbURL: URL(fileURLWithPath: "/adb"), runner: runner)

        _ = try await client.run(serial: "ABC123", arguments: ["shell", "id"], timeout: .seconds(1))

        let requests = await runner.recordedRequests()
        XCTAssertEqual(requests.first?.arguments, ["-s", "ABC123", "shell", "id"])
    }
}

private actor FakeCommandRunner: CommandRunning {
    private let result: CommandResult
    private var requests: [CommandRequest] = []

    init(result: CommandResult) { self.result = result }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        return result
    }

    nonisolated func stream(_ request: CommandRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }

    func recordedRequests() -> [CommandRequest] { requests }
}

