import Foundation
import XCTest
@testable import AndroidMonitorCore

final class ToolServicesTests: XCTestCase {
    func testParsesNulSeparatedRemotePaths() throws {
        let data = Data("/sdcard/DCIM\0/sdcard/My File.txt\0".utf8)
        let files = RemoteFileParser.paths(data)
        XCTAssertEqual(files.map(\.name), ["DCIM", "My File.txt"])
    }

    func testBuildsQuotedDeleteCommand() async throws {
        let adb = RecordingADB()
        let service = FileService(adb: adb, serial: "A")
        try await service.remove("/sdcard/a'; id")
        let arguments = await adb.lastArguments()
        XCTAssertEqual(arguments, ["shell", "rm", "-rf", "--", "'/sdcard/a'\"'\"'; id'"])
    }

    func testListingSharedStorageResolvesSdcardSymlink() async throws {
        let adb = RecordingADB()
        let service = FileService(adb: adb, serial: "A")
        _ = try await service.list("/sdcard")
        let arguments = await adb.lastArguments()
        XCTAssertEqual(arguments, ["exec-out", "sh", "-c", "find '/storage/emulated/0' -mindepth 1 -maxdepth 1 -print0"])
    }

    func testParsesPackageRows() {
        let text = "package:/data/app/base.apk=com.example.app\npackage:/system/app/x.apk=com.android.x\n"
        XCTAssertEqual(PackageOutputParser.packages(text).map(\.identifier), ["com.example.app", "com.android.x"])
    }

    func testParsesEpochLogcatRow() {
        let row = "1762162201.123  123  456 I DemoTag: hello world"
        let entry = LogcatParser.entry(row)
        XCTAssertEqual(entry?.pid, 123)
        XCTAssertEqual(entry?.priority, .info)
        XCTAssertEqual(entry?.tag, "DemoTag")
        XCTAssertEqual(entry?.message, "hello world")
    }

    func testParsesDeviceProperties() {
        let text = "[ro.product.manufacturer]: [Google]\n[ro.product.model]: [Pixel 8]\n[ro.build.version.release]: [15]\n"
        let info = DeviceInfoParser.properties(text)
        XCTAssertEqual(info.manufacturer, "Google")
        XCTAssertEqual(info.model, "Pixel 8")
        XCTAssertEqual(info.androidVersion, "15")
    }
}

private actor RecordingADB: ADBServing {
    private var arguments: [String] = []
    func devices() async throws -> [AndroidDevice] { [] }
    nonisolated func trackDevices() -> AsyncThrowingStream<[AndroidDevice], Error> { AsyncThrowingStream { $0.finish() } }
    func run(serial: String, arguments: [String], timeout: Duration) async throws -> CommandResult {
        self.arguments = arguments
        return .init(stdout: Data(), stderr: Data(), exitCode: 0)
    }
    nonisolated func stream(serial: String, arguments: [String]) -> AsyncThrowingStream<Data, Error> { AsyncThrowingStream { $0.finish() } }
    func lastArguments() -> [String] { arguments }
}

