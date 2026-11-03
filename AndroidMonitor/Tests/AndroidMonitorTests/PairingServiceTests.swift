import Foundation
import XCTest
@testable import AndroidMonitorCore

final class PairingServiceTests: XCTestCase {
    func testPairingCodeGoesThroughStdinNotArguments() async throws {
        let runner = PairingRunnerSpy()
        let service = PairingService(adbURL: URL(fileURLWithPath: "/adb"), runner: runner)

        try await service.pair(host: "192.168.1.5", port: 37123, code: "123456")

        let request = await runner.request()
        XCTAssertEqual(request?.arguments, ["pair", "192.168.1.5:37123"])
        XCTAssertEqual(request?.stdin, Data("123456\n".utf8))
    }

    func testRejectsInvalidPortBeforeRunningADB() async {
        let runner = PairingRunnerSpy()
        let service = PairingService(adbURL: URL(fileURLWithPath: "/adb"), runner: runner)

        do {
            try await service.pair(host: "phone.local", port: 0, code: "123456")
            XCTFail("Expected invalid endpoint")
        } catch {
            XCTAssertEqual(error as? PairingError, .invalidEndpoint)
        }
        let request = await runner.request()
        XCTAssertNil(request)
    }
}

private actor PairingRunnerSpy: CommandRunning {
    private var captured: CommandRequest?
    func run(_ request: CommandRequest) async throws -> CommandResult {
        captured = request
        return CommandResult(stdout: Data("Successfully paired".utf8), stderr: Data(), exitCode: 0)
    }
    nonisolated func stream(_ request: CommandRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func request() -> CommandRequest? { captured }
}

