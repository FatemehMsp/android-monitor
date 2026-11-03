import Foundation
import XCTest
@testable import AndroidMonitorCore

final class AnnexBParserTests: XCTestCase {
    func testSplitsNalUnitsAcrossChunks() {
        var parser = AnnexBParser()
        XCTAssertTrue(parser.append(Data([0, 0, 0, 1, 0x67, 1, 2, 0, 0])).isEmpty)
        let units = parser.append(Data([1, 0x68, 3, 0, 0, 0, 1, 0x65, 4]))
        XCTAssertEqual(units, [Data([0x67, 1, 2]), Data([0x68, 3])])
        XCTAssertEqual(parser.finish(), [Data([0x65, 4])])
    }

    func testReportsH264NalType() {
        XCTAssertEqual(H264NALUnit(data: Data([0x67]))?.type, .sequenceParameterSet)
        XCTAssertEqual(H264NALUnit(data: Data([0x68]))?.type, .pictureParameterSet)
        XCTAssertEqual(H264NALUnit(data: Data([0x65]))?.type, .idrSlice)
    }
}

