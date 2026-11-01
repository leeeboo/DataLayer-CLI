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

    func testScaleLocksPreserveCurrentRatioAndUnlockAllowsIndependentAxes() throws {
        var transform = VideoTransform()
        XCTAssertTrue(transform.isScaleLocked)
        transform.setScaleX(1.5)
        XCTAssertEqual(transform.scaleX, 1.5)
        XCTAssertEqual(transform.scaleY, 1.5)
        transform.isScaleLocked = false
        transform.setScaleY(0.5)
        XCTAssertEqual(transform.scaleX, 1.5)
        XCTAssertEqual(transform.scaleY, 0.5)
        transform.isScaleLocked = true
        transform.setScaleX(2)
        XCTAssertEqual(transform.scaleX, 2)
        XCTAssertEqual(transform.scaleY, 2.0 / 3, accuracy: 0.000001)
        transform.setScaleY(1)
        XCTAssertEqual(transform.scaleX, 3)
        XCTAssertEqual(transform.scaleY, 1)
        let saved = try JSONDecoder().decode(VideoTransform.self, from: JSONEncoder().encode(transform))
        XCTAssertEqual(saved, transform)
    }

    func testSpatialDefaultsResetAndLimitsPreserveMirrors() throws {
        let legacy = try JSONDecoder().decode(VideoTransform.self, from: Data(#"{"quarterTurns":1,"flipHorizontal":true}"#.utf8))
        XCTAssertEqual(legacy.scaleX, 1)
        XCTAssertEqual(legacy.scaleY, 1)
        XCTAssertTrue(legacy.isScaleLocked)
        XCTAssertEqual(legacy.positionX, 0)
        var transform = VideoTransform(quarterTurns: 1, flipHorizontal: true, scaleX: 1.5, scaleY: 0.5,
            isScaleLocked: false, positionX: 0.5, positionY: -0.25)
        transform.setScaleX(0)
        XCTAssertEqual(transform.scaleX, 0.01)
        transform.setScaleY(99999)
        XCTAssertEqual(transform.scaleY, 99.99)
        transform.positionX = .infinity
        XCTAssertEqual(transform.positionX, 0)
        transform.resetScaleAndPosition()
        XCTAssertEqual(transform.quarterTurns, 1)
        XCTAssertTrue(transform.flipHorizontal)
        XCTAssertEqual(transform.scaleX, 1)
        XCTAssertEqual(transform.scaleY, 1)
        XCTAssertEqual(transform.positionY, 0)
        XCTAssertTrue(transform.isScaleLocked)
    }

    func testSpatialSettingsRequireNewSchemaAndSurviveSplitting() throws {
        let transform = VideoTransform(scaleX: 1.5, scaleY: 0.5, isScaleLocked: false, positionX: 0.5, positionY: -0.25)
        var project = TimelineProject(outputWidth: 640, outputHeight: 360, framesPerSecond: 10, distanceUnit: .kilometers,
            tracks: [TimelineTrack(id: "v", kind: .video, name: "V", clips: [
                TimelineClip(id: "c", assetID: "source", timelineStart: 0, duration: 2, videoTransform: transform)])], schemaVersion: 5)
        let data = try JSONEncoder().encode(project)
        project = try JSONDecoder().decode(TimelineProject.self, from: data)
        XCTAssertEqual(project.schemaVersion, 6)
        XCTAssertEqual(project.splitClips(atTimelineTime: 1), 1)
        XCTAssertEqual(project.tracks[0].clips.map(\.videoTransform), [transform, transform])
    }

    func testPortableSpatialFiltersProduceExpectedPixelsAndBoundedFrames() throws {
        #if os(Windows)
        let binary = "ffmpeg.exe", separator: Character = ";"
        #else
        let binary = "ffmpeg", separator: Character = ":"
        #endif
        let search = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: separator)
        guard let executable = search.map({ URL(fileURLWithPath: String($0)).appendingPathComponent(binary) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw XCTSkip("FFmpeg is not installed in this test environment")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = "color=c=red:s=64x64:r=1:d=1,drawbox=x=32:y=0:w=32:h=32:color=lime:t=fill,drawbox=x=0:y=32:w=32:h=32:color=blue:t=fill,drawbox=x=32:y=32:w=32:h=32:color=yellow:t=fill"
        let cases: [(VideoTransform, [(Int, Int, Int)])] = [
            (VideoTransform(scaleX: 0.5, scaleY: 0.5, positionX: 0.5, positionY: 0.5),
                [(40,8,0), (56,8,1), (40,24,2), (56,24,3), (8,8,4), (48,48,4)]),
            (VideoTransform(quarterTurns: 1, scaleX: 0.5),
                [(8,24,2), (56,24,0), (8,40,3), (56,40,1), (32,8,4)]),
            (VideoTransform(quarterTurns: 3, flipHorizontal: true, scaleX: 0.5),
                [(8,24,0), (56,24,2), (8,40,1), (56,40,3), (32,8,4)]),
            (VideoTransform(scaleX: 99.99, scaleY: 99.99), [])
        ]
        let palette = [[255,0,0], [0,255,0], [0,0,255], [255,255,0], [0,0,0]]
        for (index, entry) in cases.enumerated() {
            let output = directory.appendingPathComponent("\(index).rgba")
            let filter = (entry.0.ffmpegGeometryFilters(width: 64, height: 64) + ["format=rgba"]).joined(separator: ",")
            let process = Process(), errors = Pipe()
            process.executableURL = executable
            process.arguments = ["-hide_banner", "-loglevel", "error", "-filter_threads", "1", "-f", "lavfi", "-i", source,
                "-vf", filter, "-frames:v", "1", "-f", "rawvideo", output.path]
            process.standardError = errors
            try process.run()
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, detail)
            let bytes = try Data(contentsOf: output)
            XCTAssertEqual(bytes.count, 64 * 64 * 4, "Extreme zoom must keep a fixed-size output canvas")
            for (x, y, color) in entry.1 {
                for channel in 0..<3 {
                    XCTAssertEqual(Double(bytes[(y * 64 + x) * 4 + channel]), Double(palette[color][channel]), accuracy: 20,
                        "case \(index), point \(x),\(y), channel \(channel)")
                }
                XCTAssertEqual(bytes[(y * 64 + x) * 4 + 3], color == 4 ? 0 : 255,
                    "Spatial edits preserve source opacity and leave uncovered pixels transparent")
            }
        }
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
    func testPositionUsesCanvasCoordinatesAndScalePrecedesRotation() {
        let size = CGSize(width: 80, height: 40)
        let geometry = VideoTransform(quarterTurns: 1, scaleX: 0.5, scaleY: 1,
            positionX: 0.5, positionY: 0.5)
        let transform = TimelineVideoCompositionBuilder.aspectFitTransform(naturalSize: size,
            preferredTransform: .identity, videoTransform: geometry, renderSize: size)
        XCTAssertEqual(CGRect(origin: .zero, size: size).applying(transform), CGRect(x: 40, y: 10, width: 40, height: 40))
        let smallerPreview = TimelineVideoCompositionBuilder.aspectFitTransform(naturalSize: size,
            preferredTransform: .identity, videoTransform: geometry, renderSize: CGSize(width: 40, height: 20))
        XCTAssertEqual(CGRect(origin: .zero, size: size).applying(smallerPreview), CGRect(x: 20, y: 5, width: 20, height: 20))
    }

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
