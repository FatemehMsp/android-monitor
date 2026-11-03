import Foundation
import XCTest
@testable import AndroidMonitorCore

final class ProcessCommandRunnerTests: XCTestCase {
    func testTimeoutReturnsBeforeProcessNaturalExit() async {
        let runner = ProcessCommandRunner()
        let request = CommandRequest(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            timeout: .milliseconds(100)
        )
        let clock = ContinuousClock()
        let started = clock.now

        do {
            _ = try await runner.run(request)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? CommandError, .timedOut)
        }

        XCTAssertLessThan(started.duration(to: clock.now), .seconds(1))
    }
}

