import Foundation
@testable import OverlayCore
import XCTest

final class VideoTransformTests: XCTestCase {
    func testQuarterTurnsAccumulateAndLegacyClipsRemainUnchanged() throws {
        var transform = VideoTransform(quarterTurns: -1, flipHorizontal: true)
        XCTAssertEqual(transform.quarterTurns, -1)
        XCTAssertEqual(transform.normalizedQuarterTurns, 3)
        transform.quarterTurns += 1
        XCTAssertEqual(transform.quarterTurns, 0)
        transform.quarterTurns -= 1
        XCTAssertEqual(transform.quarterTurns, -1)
        transform.quarterTurns = 5
        XCTAssertEqual(transform.rotationDegrees, 450)
        XCTAssertEqual(transform.normalizedQuarterTurns, 1)
        let json = Data(#"{"id":"v","assetID":"source","timelineStart":0,"duration":1}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(TimelineClip.self, from: json).videoTransform, .identity)
        XCTAssertEqual(try JSONDecoder().decode(VideoTransform.self, from: Data(#"{"quarterTurns":-5}"#.utf8)).quarterTurns, -5)
    }

    func testProjectSaveReloadPreservesVideoOnlySettings() throws {
        let transform = VideoTransform(quarterTurns: 1, flipHorizontal: true, flipVertical: true)
        let clip = TimelineClip(id: "v", assetID: "source", timelineStart: 0, duration: 2, videoTransform: transform)
        let project = TimelineProject(outputWidth: 64, outputHeight: 64, framesPerSecond: 2, distanceUnit: .kilometers,
            tracks: [TimelineTrack(id: "video", kind: .video, name: "V", clips: [clip]),
                     TimelineTrack(id: "overlay", kind: .overlay, name: "O", clips: [
                        TimelineClip(id: "o", assetID: "activity", timelineStart: 0, duration: 2, layout: .default)
                     ])])
        var decoded = try JSONDecoder().decode(TimelineProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.tracks[1].clips[0].videoTransform, .identity)
        XCTAssertEqual(decoded.tracks[1].clips[0].layout, .default)
        XCTAssertEqual(decoded.splitClips(atTimelineTime: 1, clipID: "v", makeClipID: { "right" }), 1)
        XCTAssertEqual(decoded.tracks[0].clips.map(\.videoTransform), [transform, transform])
        XCTAssertEqual(decoded.tracks[1], project.tracks[1])
    }

    func testPortableFiltersFlipSourceAxesBeforeRotation() {
        XCTAssertEqual(VideoTransform(quarterTurns: 1, flipHorizontal: true).ffmpegFilters, ["hflip", "transpose=clock"])
        XCTAssertEqual(VideoTransform(quarterTurns: 2, flipVertical: true).ffmpegFilters, ["vflip", "hflip", "vflip"])
        XCTAssertEqual(VideoTransform(quarterTurns: 3).ffmpegFilters, ["transpose=cclock"])
        XCTAssertEqual(VideoTransform.identity.ffmpegFilters, [])
    }

    func testLegacyProjectOnlyUpgradesSchemaWhenOrientationRequiresIt() throws {
        var project = TimelineProject(outputWidth: 64, outputHeight: 64, framesPerSecond: 2, distanceUnit: .kilometers,
            tracks: [TimelineTrack(id: "v", kind: .video, name: "V", clips: [
                TimelineClip(id: "c", assetID: "source", timelineStart: 0, duration: 1)])], schemaVersion: 2)
        func savedVersion() throws -> Int {
            try JSONDecoder().decode(TimelineProject.self, from: JSONEncoder().encode(project)).schemaVersion
        }
        XCTAssertEqual(try savedVersion(), 2)
        project.tracks[0].clips[0].colorSettings = VideoColorSettings(input: .rec709)
        XCTAssertEqual(try savedVersion(), 4)
        project.tracks[0].clips[0].videoTransform = VideoTransform(quarterTurns: 1)
        XCTAssertEqual(try savedVersion(), 5)
    }

    #if canImport(CoreGraphics)
    func testQuarterTurnKeepsOriginalScaleAndCanvasCenter() {
        let size = CGSize(width: 80, height: 40)
        let transform = TimelineVideoCompositionBuilder.aspectFitTransform(naturalSize: size,
            preferredTransform: .identity, videoTransform: VideoTransform(quarterTurns: 1), renderSize: size)
        XCTAssertEqual(CGRect(origin: .zero, size: size).applying(transform), CGRect(x: 20, y: -20, width: 40, height: 80))
    }

    func testAllOrientationsNormalizeBoundsAndPreserveMetadata() {
        let size = CGSize(width: 80, height: 40)
        let metadata = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 40, ty: 0)
        for turns in 0..<4 {
            for horizontal in [false, true] {
                for vertical in [false, true] {
                    let geometry = VideoTransform(quarterTurns: turns, flipHorizontal: horizontal, flipVertical: vertical)
                    let transform = geometry.sourceTransform(naturalSize: size, preferredTransform: metadata)
                    let rect = CGRect(origin: .zero, size: size).applying(transform)
                    XCTAssertEqual(rect.origin, .zero)
                    XCTAssertEqual(rect.size, turns.isMultiple(of: 2) ? CGSize(width: 40, height: 80) : size)
                    XCTAssertEqual(abs(transform.a * transform.d - transform.b * transform.c), 1)
                }
            }
        }
    }
    #endif
}
