import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@testable import OverlayCore
import XCTest

final class LazyTimelineSegmentReaderStressTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // The regression this covers used to stall before the first rendered frame. Keep a
        // runner-level guard so a recurrence cannot leave the test process waiting forever.
        executionTimeAllowance = 30
    }

    func testTwentyThreeMixedSegmentsDecodeAtBoundariesAfterInitialGap() async throws {
        let segmentCount = 23
        let frameDuration = 1.0 / 6.0
        let sourceURLs = (0..<segmentCount).map { temporaryMovieURL("lazy-segment-\($0)") }
        let outputURL = temporaryMovieURL("lazy-segment-stress-output")
        defer {
            (sourceURLs + [outputURL]).forEach(removeTemporaryFile)
        }

        let fixtures = (0..<segmentCount).map { index in fixture(for: index) }
        do {
            for (index, url) in sourceURLs.enumerated() {
                let fixture = fixtures[index]
                try makeSourceVideo(at: url, fixture: fixture)
            }
        } catch let error as OverlayVideoError where error.isUnavailableTimelineTestEncoder {
            throw XCTSkip("Mixed H.264/HEVC source encoder is unavailable on this Mac: \(error.description)")
        }

        let hevcAsset = AVURLAsset(url: sourceURLs[1])
        let hevcTracks = try await hevcAsset.loadTracks(withMediaType: .video)
        let hevcTrack = try XCTUnwrap(hevcTracks.first)
        let hevcDescriptions = try await hevcTrack.load(.formatDescriptions)
        let hevcDescription = try XCTUnwrap(hevcDescriptions.first)
        XCTAssertEqual(
            CMFormatDescriptionGetMediaSubType(hevcDescription),
            kCMVideoCodecType_HEVC,
            "The stress fixture must include an hvc1/HEVC source."
        )

        let clips = fixtures.enumerated().map { index, fixture in
            TimelineClip(
                id: "clip-\(index)",
                assetID: "video-\(index)",
                timelineStart: frameDuration + Double(index) * frameDuration,
                duration: frameDuration,
                sourceIn: fixture.sourceIn
            )
        }
        let outputDuration = frameDuration + Double(segmentCount) * frameDuration
        let assets = fixtures.enumerated().map { index, fixture in
            MediaAsset(
                id: "video-\(index)",
                kind: .video,
                url: sourceURLs[index],
                displayName: sourceURLs[index].lastPathComponent,
                duration: fixture.sourceDuration,
                width: fixture.displayWidth,
                height: fixture.displayHeight,
                framesPerSecond: Double(fixture.framesPerSecond)
            )
        } + [
            MediaAsset(
                id: "activity",
                kind: .activity,
                url: URL(fileURLWithPath: "/tmp/lazy-segment-stress.fit"),
                displayName: "lazy-segment-stress.fit",
                duration: outputDuration
            )
        ]
        let project = TimelineProject(
            outputWidth: 64,
            outputHeight: 64,
            framesPerSecond: 6,
            distanceUnit: .kilometers,
            assets: assets,
            tracks: [
                TimelineTrack(id: "video", kind: .video, name: "V1", clips: clips),
                TimelineTrack(id: "overlay", kind: .overlay, name: "O1", clips: [
                    TimelineClip(
                        id: "empty-overlay",
                        assetID: "activity",
                        timelineStart: 0,
                        duration: outputDuration,
                        layout: OverlayLayout(elements: [])
                    )
                ])
            ]
        )

        let built = try TimelineVideoCompositionBuilder.make(
            project: project,
            videoClips: clips,
            requiredEnd: outputDuration,
            renderSize: CGSize(width: 64, height: 64),
            framesPerSecond: 6
        )
        XCTAssertEqual(built.videoRanges.count, segmentCount)
        XCTAssertGreaterThan(
            built.composition.tracks(withMediaType: .video).count,
            1,
            "The fixture must retain incompatible source groups that formerly stalled a composition reader at frame 0."
        )

        let readerEvents = PrepareReaderEventRecorder()
        let writer = TimelineVideoWriter(
            outputURL: outputURL,
            project: project,
            telemetrySeriesByAssetID: ["activity": syntheticSeries(duration: outputDuration)],
            config: TimelineVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 6,
                duration: outputDuration,
                averageBitRate: 300_000,
                codec: .h264,
                diagnosticsHandler: { event in
                    readerEvents.record(event)
                }
            )
        )
        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableTimelineTestEncoder {
            throw XCTSkip("Timeline stress output encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertGreaterThan(try outputFileSize(outputURL), 0)
        XCTAssertEqual(
            readerEvents.count(stage: .prepareReader, phase: .begin),
            segmentCount,
            "Each timeline segment must open its own original-source reader."
        )
        XCTAssertEqual(
            readerEvents.count(stage: .prepareReader, phase: .end),
            segmentCount,
            "Each timeline segment reader must successfully begin reading."
        )
        let firstGapFrameIsBlack = try await isNearBlackFrame(from: outputURL, at: 0)
        XCTAssertTrue(firstGapFrameIsBlack, "The initial timeline gap must remain black.")
        let lastGapFrameIsBlack = try await isNearBlackFrame(from: outputURL, at: frameDuration - 0.01)
        XCTAssertTrue(lastGapFrameIsBlack, "The gap must end exactly at the first clip boundary.")

        for (index, fixture) in fixtures.enumerated() {
            let boundary = frameDuration + Double(index) * frameDuration
            let time = boundary + frameDuration * 0.2
            let color = try await centerRGB(from: outputURL, at: time)
            XCTAssertGreaterThan(
                color.component(named: fixture.dominantChannel),
                color.largestOther(than: fixture.dominantChannel) + 65,
                "Segment \(index) decoded the wrong source at \(time)s."
            )
        }

        let firstSegment = try await centerRGB(from: outputURL, at: frameDuration)
        XCTAssertGreaterThan(firstSegment.red, firstSegment.green + 65, "The sourceIn frame must be rendered at the first boundary.")
        let lastSegmentTime = frameDuration + Double(segmentCount - 1) * frameDuration
        let lastSegment = try await centerRGB(from: outputURL, at: lastSegmentTime + frameDuration * 0.2)
        XCTAssertGreaterThan(
            lastSegment.component(named: fixtures.last!.dominantChannel),
            lastSegment.largestOther(than: fixtures.last!.dominantChannel) + 65,
            "The final source frame must not be dropped."
        )
    }

    func testNineteenSimultaneouslyActiveOverlaysAcrossThreeActivitiesKeepVideoVisible() async throws {
        let sourceURL = temporaryMovieURL("nineteen-overlays-source")
        let outputURL = temporaryMovieURL("nineteen-overlays-output")
        defer {
            [sourceURL, outputURL].forEach(removeTemporaryFile)
        }

        do {
            try makeSourceVideo(at: sourceURL, fixture: fixture(for: 0), firstFrameIsBlack: false)
        } catch let error as OverlayVideoError where error.isUnavailableTimelineTestEncoder {
            throw XCTSkip("Nineteen-overlay source encoder is unavailable on this Mac: \(error.description)")
        }

        let duration = 1.0
        let activityAssets = (0..<3).map { index in
            MediaAsset(
                id: "activity-\(index)",
                kind: .activity,
                url: URL(fileURLWithPath: "/tmp/nineteen-overlays-\(index).fit"),
                displayName: "nineteen-overlays-\(index).fit",
                duration: duration
            )
        }
        let overlayTracks = (0..<19).map { index in
            TimelineTrack(id: "overlay-\(index)", kind: .overlay, name: "O\(index)", clips: [
                TimelineClip(
                    id: "overlay-clip-\(index)",
                    assetID: activityAssets[index % activityAssets.count].id,
                    timelineStart: 0,
                    duration: duration,
                    layout: OverlayLayout(elements: [])
                )
            ])
        }
        let project = TimelineProject(
            outputWidth: 64,
            outputHeight: 64,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            assets: [
                MediaAsset(
                    id: "video",
                    kind: .video,
                    url: sourceURL,
                    displayName: sourceURL.lastPathComponent,
                    duration: 1,
                    width: 64,
                    height: 64,
                    framesPerSecond: 6
                )
            ] + activityAssets,
            tracks: [
                TimelineTrack(id: "video", kind: .video, name: "V1", clips: [
                    TimelineClip(id: "video-clip", assetID: "video", timelineStart: 0, duration: duration)
                ])
            ] + overlayTracks
        )
        XCTAssertEqual(project.activeClips(kind: .overlay, atTimelineTime: 0.5).count, 19)

        let writer = TimelineVideoWriter(
            outputURL: outputURL,
            project: project,
            telemetrySeriesByAssetID: Dictionary(
                uniqueKeysWithValues: activityAssets.enumerated().map { index, asset in
                    (asset.id, syntheticSeries(duration: duration + Double(index)))
                }
            ),
            config: TimelineVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: duration,
                averageBitRate: 200_000,
                codec: .h264
            )
        )
        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableTimelineTestEncoder {
            throw XCTSkip("Nineteen-overlay output encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertGreaterThan(try outputFileSize(outputURL), 0)
        for time in [0.25, 0.75] {
            let color = try await centerRGB(from: outputURL, at: time)
            XCTAssertGreaterThan(color.red, max(color.green, color.blue) + 65, "Overlay composition replaced the base video at \(time)s.")
        }
    }

    private struct Fixture {
        let codec: AVVideoCodecType
        let width: Int
        let height: Int
        let framesPerSecond: Int32
        let transform: CGAffineTransform
        let color: (UInt8, UInt8, UInt8)
        let dominantChannel: String

        let sourceIn = 1.0 / 6.0
        let sourceDuration = 1.0

        var displayWidth: Int { transform.isIdentity ? width : height }
        var displayHeight: Int { transform.isIdentity ? height : width }
    }

    private func fixture(for index: Int) -> Fixture {
        switch index % 3 {
        case 0:
            return Fixture(codec: .h264, width: 64, height: 64, framesPerSecond: 6, transform: .identity, color: (225, 20, 20), dominantChannel: "red")
        case 1:
            return Fixture(codec: .hevc, width: 96, height: 64, framesPerSecond: 5, transform: .identity, color: (20, 225, 20), dominantChannel: "green")
        default:
            return Fixture(codec: .h264, width: 64, height: 96, framesPerSecond: 6, transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 96, ty: 0), color: (20, 40, 225), dominantChannel: "blue")
        }
    }

    private func makeSourceVideo(at url: URL, fixture: Fixture, firstFrameIsBlack: Bool = true) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: fixture.codec,
                AVVideoWidthKey: fixture.width,
                AVVideoHeightKey: fixture.height
            ]
        )
        input.expectsMediaDataInRealTime = false
        input.transform = fixture.transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: fixture.width,
                kCVPixelBufferHeightKey as String: fixture.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(input) else {
            throw OverlayVideoError.unsupportedEncoder("Could not create lazy segment fixture input.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw OverlayVideoError.cannotStartWriter(writer.error?.localizedDescription ?? "Could not start lazy segment fixture writer.")
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(fixture.sourceDuration * Double(fixture.framesPerSecond))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            let color: (UInt8, UInt8, UInt8) = firstFrameIsBlack && frame == 0 ? (0, 0, 0) : fixture.color
            guard adaptor.append(
                try makePixelBuffer(width: fixture.width, height: fixture.height, color: color),
                withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fixture.framesPerSecond)
            ) else {
                throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Could not append lazy segment fixture frame.")
            }
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else {
            throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Lazy segment fixture writer failed.")
        }
    }

    private func makePixelBuffer(width: Int, height: Int, color: (UInt8, UInt8, UInt8)) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = color.2
                bytes[offset + 1] = color.1
                bytes[offset + 2] = color.0
                bytes[offset + 3] = 255
            }
        }
        return pixelBuffer
    }

    private func centerRGB(from url: URL, at seconds: TimeInterval) async throws -> RGB {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: seconds, preferredTimescale: 600), duration: CMTime(seconds: 0.1, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let sample = try XCTUnwrap(output.copyNextSampleBuffer())
        let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let x = CVPixelBufferGetWidth(buffer) / 2
        let y = CVPixelBufferGetHeight(buffer) / 2
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        return RGB(red: Double(bytes[offset + 2]), green: Double(bytes[offset + 1]), blue: Double(bytes[offset]))
    }

    private func isNearBlackFrame(from url: URL, at seconds: TimeInterval) async throws -> Bool {
        let color = try await centerRGB(from: url, at: seconds)
        return max(color.red, color.green, color.blue) < 35
    }

    private func syntheticSeries(duration: Double) -> TelemetrySeries {
        TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: duration, distanceMeters: duration)
        ])
    }

    private func temporaryMovieURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)").appendingPathExtension("mov")
    }

    private func removeTemporaryFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func outputFileSize(_ url: URL) throws -> UInt64 {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64)
    }
}

private struct RGB {
    let red: Double
    let green: Double
    let blue: Double

    func component(named name: String) -> Double {
        switch name {
        case "red": red
        case "green": green
        default: blue
        }
    }

    func largestOther(than name: String) -> Double {
        switch name {
        case "red": max(green, blue)
        case "green": max(red, blue)
        default: max(red, green)
        }
    }
}

private final class PrepareReaderEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [VideoExportDiagnosticEvent.Stage: [VideoExportDiagnosticEvent.Phase: Int]] = [:]

    func record(_ event: VideoExportDiagnosticEvent) {
        guard event.stage == .prepareReader else { return }
        lock.lock()
        counts[event.stage, default: [:]][event.phase, default: 0] += 1
        lock.unlock()
    }

    func count(stage: VideoExportDiagnosticEvent.Stage, phase: VideoExportDiagnosticEvent.Phase) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[stage]?[phase, default: 0] ?? 0
    }
}

private extension OverlayVideoError {
    var isUnavailableTimelineTestEncoder: Bool {
        switch self {
        case .unsupportedEncoder, .cannotStartWriter:
            true
        case let .writerFailed(message, _):
            message.localizedCaseInsensitiveContains("encoder") || message.contains("-12903")
        case .unreadableVideo, .cannotCreatePixelBuffer, .cannotCreateBitmapContext, .invalidConfiguration, .cancelled:
            false
        }
    }
}
