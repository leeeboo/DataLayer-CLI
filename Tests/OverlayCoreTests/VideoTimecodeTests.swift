import XCTest
@testable import OverlayCore

final class VideoTimecodeTests: XCTestCase {
    func testDecodedProjectWithUnrepresentablePreviewTimeDoesNotTrap() throws {
        let project = try JSONDecoder().decode(TimelineProject.self, from: Data("""
        {"outputWidth":1920,"outputHeight":1080,"framesPerSecond":30,"distanceUnit":"km","previewTime":1e100}
        """.utf8))
        XCTAssertEqual(VideoTimecode.string(at: try XCTUnwrap(project.previewTime),
            framesPerSecond: project.framesPerSecond, mode: .nonDropFrame), "00:00:00:00")
    }

    func testUnrepresentableFrameRatesAndFullIntegerFrameRangeDoNotTrap() {
        for rate in [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, Double.infinity, Double.nan] {
            XCTAssertEqual(VideoTimecode.string(frameNumber: 30, framesPerSecond: rate, mode: .nonDropFrame),
                rate == -Double.greatestFiniteMagnitude ? "00:00:30:00" : "00:00:01:00")
        }
        XCTAssertEqual(VideoTimecode.string(frameNumber: .max, framesPerSecond: 30_000.0 / 1_001.0, mode: .dropFrame),
            "85487080013854:22:15;29")
    }

    func testPreferredDisplayModeUsesDFOnlyForFractionalNTSCRates() {
        XCTAssertEqual(VideoTimecode.preferredDisplayMode(for: 29.97), .dropFrame)
        XCTAssertEqual(VideoTimecode.preferredDisplayMode(for: 60_000.0 / 1_001.0), .dropFrame)
        XCTAssertEqual(VideoTimecode.preferredDisplayMode(for: 30), .nonDropFrame)
        XCTAssertEqual(VideoTimecode.preferredDisplayMode(for: 25), .nonDropFrame)
    }

    func testNDFUsesAbsoluteFrameCountAtNTSCFrameRate() {
        XCTAssertEqual(
            VideoTimecode.string(
                frameNumber: 1_800,
                framesPerSecond: 30_000.0 / 1_001.0,
                mode: .nonDropFrame
            ),
            "00:01:00:00"
        )
    }

    func test29_97DFSkipsLabelsAtOrdinaryMinuteButNotTenMinuteBoundary() {
        let frameRate = 30_000.0 / 1_001.0
        XCTAssertEqual(
            VideoTimecode.string(frameNumber: 1_799, framesPerSecond: frameRate, mode: .dropFrame),
            "00:00:59;29"
        )
        XCTAssertEqual(
            VideoTimecode.string(frameNumber: 1_800, framesPerSecond: frameRate, mode: .dropFrame),
            "00:01:00;02"
        )
        XCTAssertEqual(
            VideoTimecode.string(frameNumber: 17_982, framesPerSecond: frameRate, mode: .dropFrame),
            "00:10:00;00"
        )
        XCTAssertEqual(
            VideoTimecode.string(frameNumber: 157_283, framesPerSecond: frameRate, mode: .dropFrame),
            "01:27:28;01"
        )
    }

    func test59_94DFSkipsFourLabelsWhileFrameTimeStaysUnchanged() {
        let frameRate = 60_000.0 / 1_001.0
        let frameNumber: Int64 = 3_600
        XCTAssertEqual(
            VideoTimecode.string(frameNumber: frameNumber, framesPerSecond: frameRate, mode: .dropFrame),
            "00:01:00;04"
        )
        XCTAssertEqual(
            VideoTimecode.string(frameNumber: frameNumber, framesPerSecond: frameRate, mode: .nonDropFrame),
            "00:01:00:00"
        )
        XCTAssertEqual(Double(frameNumber) / frameRate, 60.06, accuracy: 0.000_000_001)
    }

    func testNonNTSCFrameRateNeverDropsLabels() {
        XCTAssertEqual(
            VideoTimecode.string(frameNumber: 1_500, framesPerSecond: 25, mode: .dropFrame),
            "00:01:00:00"
        )
    }
}
