import CoreMedia
import XCTest
@testable import OverlayCore

final class FrameRateCanonicalizerTests: XCTestCase {
    func testNTSCAliasesCanonicalizeToExactRates() {
        XCTAssertEqual(FrameRateCanonicalizer.canonicalize(23.976), 24_000.0 / 1_001.0)
        XCTAssertEqual(FrameRateCanonicalizer.canonicalize(24_000.0 / 1_001.0), 24_000.0 / 1_001.0)
        XCTAssertEqual(FrameRateCanonicalizer.canonicalize(29.97), 30_000.0 / 1_001.0)
        XCTAssertEqual(FrameRateCanonicalizer.canonicalize(30_000.0 / 1_001.0), 30_000.0 / 1_001.0)
        XCTAssertEqual(FrameRateCanonicalizer.canonicalize(59.94), 60_000.0 / 1_001.0)
        XCTAssertEqual(FrameRateCanonicalizer.canonicalize(60_000.0 / 1_001.0), 60_000.0 / 1_001.0)
    }

    func testOtherRatesAndInvalidValuesRemainAvailableToCallerValidation() {
        XCTAssertEqual(FrameRateCanonicalizer.canonicalize(24), 24)
        XCTAssertEqual(FrameRateCanonicalizer.canonicalize(.nan).isNaN, true)
        XCTAssertEqual(FrameRateCanonicalizer.canonicalize(.infinity), .infinity)
    }

    func testNTSCFrameDurationUsesExactRational() {
        let duration = FrameRateCanonicalizer.frameDuration(for: 29.97)
        XCTAssertEqual(duration.value, 1_001)
        XCTAssertEqual(duration.timescale, 30_000)
        XCTAssertEqual(FrameRateCanonicalizer.exactFrameDuration(for: 24), nil)
    }

    func testTimelineTimescalePreservesLongNTSCFramePositions() {
        let rate = FrameRateCanonicalizer.ntsc29_97
        let frameNumber = Int64((4 * 60 * 60 * rate).rounded(.down))
        let position = CMTime(
            seconds: Double(frameNumber) / rate,
            preferredTimescale: FrameRateCanonicalizer.timelineTimescale
        )

        XCTAssertEqual(position, CMTime(
            value: frameNumber * 4_004,
            timescale: FrameRateCanonicalizer.timelineTimescale
        ))
    }
}
