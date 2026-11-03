import Foundation
import XCTest
@testable import AndroidMonitorCore

final class PrivilegeTests: XCTestCase {
    func testQuotesHostileRemotePathAsOneArgument() {
        XCTAssertEqual(
            RemoteShell.quote("/sdcard/a'; rm -rf /"),
            "'/sdcard/a'\"'\"'; rm -rf /'"
        )
    }

    func testDetectsGrantedRoot() async throws {
        let adb = PrivilegeADBStub { arguments in
            XCTAssertEqual(arguments, ["shell", "su", "-c", "id"])
            return CommandResult(stdout: Data("uid=0(root) gid=0(root)".utf8), stderr: Data(), exitCode: 0)
        }
        let detector = PrivilegeDetector(adb: adb, serial: "A")
        let granted = try await detector.detectRoot()
        XCTAssertTrue(granted)
    }

    func testDetectsDebuggablePackage() async throws {
        let adb = PrivilegeADBStub { arguments in
            XCTAssertEqual(arguments, ["shell", "run-as", "com.example.app", "id"])
            return CommandResult(stdout: Data("uid=10123".utf8), stderr: Data(), exitCode: 0)
        }
        let detector = PrivilegeDetector(adb: adb, serial: "A")
        let allowed = try await detector.canRunAs(package: "com.example.app")
        XCTAssertTrue(allowed)
    }

    func testRejectsUnsafePackageIdentifier() async {
        let adb = PrivilegeADBStub { _ in XCTFail("ADB must not run"); return .init(stdout: Data(), stderr: Data(), exitCode: 0) }
        let detector = PrivilegeDetector(adb: adb, serial: "A")
        do {
            _ = try await detector.canRunAs(package: "com.app;id")
            XCTFail("Expected invalid package")
        } catch {
            XCTAssertEqual(error as? PrivilegeError, .invalidPackageIdentifier)
        }
    }

    func testRootReadUsesExplicitSuCommand() async throws {
        let runner = PrivilegeRunnerSpy()
        let service = ProtectedDataService(adbURL: URL(fileURLWithPath: "/adb"), runner: runner, serial: "A")
        _ = try await service.read(path: "/data/data/a db/file", access: .root)
        let request = await runner.request()
        XCTAssertEqual(request?.arguments, ["-s", "A", "exec-out", "su", "-c", "cat -- '/data/data/a db/file'"])
    }
}

private struct PrivilegeADBStub: ADBServing {
    let handler: @Sendable ([String]) async throws -> CommandResult
    init(handler: @escaping @Sendable ([String]) async throws -> CommandResult) { self.handler = handler }
    func devices() async throws -> [AndroidDevice] { [] }
    func trackDevices() -> AsyncThrowingStream<[AndroidDevice], Error> { AsyncThrowingStream { $0.finish() } }
    func run(serial: String, arguments: [String], timeout: Duration) async throws -> CommandResult { try await handler(arguments) }
    func stream(serial: String, arguments: [String]) -> AsyncThrowingStream<Data, Error> { AsyncThrowingStream { $0.finish() } }
}

private actor PrivilegeRunnerSpy: CommandRunning {
    private var captured: CommandRequest?
    func run(_ request: CommandRequest) async throws -> CommandResult { captured = request; return .init(stdout: Data(), stderr: Data(), exitCode: 0) }
    nonisolated func stream(_ request: CommandRequest) -> AsyncThrowingStream<Data, Error> { AsyncThrowingStream { $0.finish() } }
    func request() -> CommandRequest? { captured }
}

