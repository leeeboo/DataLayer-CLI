import AudioToolbox
import AVFoundation
import CoreMedia
import CoreVideo
@testable import OverlayCore
import XCTest

final class CompositedVideoWriterTests: XCTestCase {
    func testActivityAndClockOffsetsAreClampedIndependently() {
        var config = CompositedVideoWriterConfig(
            width: 64,
            height: 64,
            framesPerSecond: 30,
            duration: 1,
            activityOffsetMilliseconds: -2_000,
            fitClockOffsetMilliseconds: 2_000
        )

        XCTAssertEqual(config.activityOffsetMilliseconds, -999)
        XCTAssertEqual(config.fitClockOffsetMilliseconds, 999)

        config.activityOffsetMilliseconds = 2_000
        config.fitClockOffsetMilliseconds = -2_000
        XCTAssertEqual(config.activityOffsetMilliseconds, 999)
        XCTAssertEqual(config.fitClockOffsetMilliseconds, -999)
    }

    func testWriterRendersTinyCompositedOutput() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composited-source-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composited-output-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: sourceURL)

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0),
                TelemetrySample(elapsed: 1, distanceMeters: 3)
            ]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: 1,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        do {
            let asset = AVURLAsset(url: outputURL)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            XCTAssertEqual(tracks.count, 1)
        }
    }

    func testUndecodableTimelineSegmentExportsBlackFramesAndWarning() async throws {
        let sourceURL = temporaryMovieURL("composited-skipped-source")
        let outputURL = temporaryMovieURL("composited-skipped-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }
        try makeTinySourceVideo(at: sourceURL)
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let segment = TimelineVideoSegment(
            clipID: "undecodable",
            sourceDisplayName: sourceURL.lastPathComponent,
            asset: asset,
            videoTrack: track,
            timelineRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)),
            sourceRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)),
            sourceTransform: .identity
        )
        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceAsset: asset,
            sourceDescription: sourceURL.lastPathComponent,
            sourceVideoSegments: [segment],
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: 1,
                averageBitRate: 200_000,
                codec: .h264
            ),
            overlayStartTime: 0,
            renderOverlay: { _, buffer in
                CVPixelBufferLockBaseAddress(buffer, [])
                if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                    memset(baseAddress, 0, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
            },
            segmentReaderAttemptFactory: { _, _, _ in FailedDecodeAttempt() }
        )

        let result: VideoExportResult
        do {
            result = try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited H.264 encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.kind, .videoSegmentSkipped)
        XCTAssertEqual(result.warnings.first?.clipID, "undecodable")
        let frames = try await videoFrameSummary(from: outputURL)
        XCTAssertEqual(frames.count, 2)
        XCTAssertLessThan(frames.lastMeanLuma, 5)
    }

    func testBlockedTimelineDecoderFailsWithoutReplacingExistingOutput() async throws {
        let sourceURL = temporaryMovieURL("composited-blocked-source")
        let outputURL = temporaryMovieURL("composited-blocked-output")
        let attempt = NonCooperativeDecodeAttempt()
        defer {
            attempt.releaseRead()
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }
        try makeTinySourceVideo(at: sourceURL)
        let existing = Data("previous completed export".utf8)
        try existing.write(to: outputURL)
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))
        let segment = TimelineVideoSegment(clipID: "blocked", sourceDisplayName: "camera.mov", asset: asset,
            videoTrack: track, timelineRange: range, sourceRange: range, sourceTransform: .identity)
        let writer = CompositedVideoWriter(outputURL: outputURL, sourceAsset: asset, sourceDescription: "camera.mov",
            sourceVideoSegments: [segment],
            config: .init(width: 64, height: 64, framesPerSecond: 2, duration: 1, averageBitRate: 200_000, codec: .h264),
            overlayStartTime: 0, renderOverlay: { _, _ in XCTFail("No frame should be rendered after a blocked read") },
            segmentReaderAttemptFactory: { _, _, _ in attempt })
        let started = ProcessInfo.processInfo.systemUptime
        do {
            _ = try writer.write()
            XCTFail("A blocked decoder must fail rather than deliver black video")
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited H.264 encoder is unavailable: \(error.description)")
        } catch {
            let cause = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            XCTAssertEqual(cause?.domain, "run.libo.datalayer-studio.decoder")
            XCTAssertEqual(cause?.code, 1)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 12)
        XCTAssertEqual(try Data(contentsOf: outputURL), existing)
        XCTAssertEqual(attempt.copyCount, 1)
        XCTAssertEqual(attempt.cancelCount, 0)
        attempt.releaseRead()
        XCTAssertEqual(attempt.cancelled.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(attempt.cancelCount, 1)
    }

    func testTinyCompositedExportReportsOrderedLifecycleDiagnostics() throws {
        let sourceURL = temporaryMovieURL("composited-diagnostics-source")
        let outputURL = temporaryMovieURL("composited-diagnostics-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }
        try makeTinySourceVideo(at: sourceURL)

        var events: [VideoExportDiagnosticEvent] = []
        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [TelemetrySample(elapsed: 0, distanceMeters: 0)]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: 1,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: []),
                diagnosticsHandler: { events.append($0) }
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited H.264 encoder is unavailable on this Mac: \(error.description)")
        }

        let lifecycleStages: Set<VideoExportDiagnosticEvent.Stage> = [
            .prepareTimeline, .prepareReader, .prepareWriter, .awaitReady, .finishInput,
            .finishWriter, .installOutput, .exportCompleted, .exportFailed
        ]
        let lifecycle = events.filter { lifecycleStages.contains($0.stage) && $0.operationStep == nil }
        XCTAssertEqual(lifecycle.count, 16)
        XCTAssertEqual(lifecycle.map { "\($0.stage.rawValue):\($0.phase.rawValue)" }, [
            "prepareTimeline:begin", "prepareTimeline:end",
            "prepareReader:begin", "prepareReader:update", "prepareWriter:begin",
            "prepareReader:end", "prepareWriter:end",
            "awaitReady:begin",
            "finishInput:begin", "finishInput:end",
            "awaitReady:end",
            "finishWriter:begin", "finishWriter:end",
            "installOutput:begin", "installOutput:end",
            "exportCompleted:end"
        ])
        XCTAssertEqual(lifecycle[3].sourceSize, .init(width: 64, height: 64))
        XCTAssertEqual(lifecycle[3].sourceHasAudio, false)
        XCTAssertNil(lifecycle.last?.errorDomain)
        XCTAssertEqual(events.compactMap(\.operationStep), [.outputCheckCompleted, .outputMove])
        XCTAssertLessThan(events.count, 32)
    }

    func testWriterRendersTrimmedCompositedOutput() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composited-trimmed-source-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composited-trimmed-output-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: sourceURL, frameCount: 4)

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0),
                TelemetrySample(elapsed: 2, distanceMeters: 6)
            ]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                startTime: 1,
                duration: 1,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    // MARK: - Configuration rejection

    func testWriterRejectsInvalidDimensionsBeforeExport() {
        assertWriterRejectsInvalidConfiguration(makeConfig(width: 0, height: 1_080))
        assertWriterRejectsInvalidConfiguration(makeConfig(width: 1_919, height: 1_080))
        assertWriterRejectsInvalidConfiguration(makeConfig(width: 1_920, height: 1_079))
        assertWriterRejectsInvalidConfiguration(makeConfig(width: 16_386, height: 1_080))
        assertWriterRejectsInvalidConfiguration(makeConfig(width: 1_920, height: 16_386))
    }

    func testWriterRejectsInvalidTimingBeforeExport() {
        assertWriterRejectsInvalidConfiguration(makeConfig(framesPerSecond: .nan))
        assertWriterRejectsInvalidConfiguration(makeConfig(framesPerSecond: 0))
        assertWriterRejectsInvalidConfiguration(makeConfig(startTime: -1))
        assertWriterRejectsInvalidConfiguration(makeConfig(startTime: .infinity))
        assertWriterRejectsInvalidConfiguration(makeConfig(duration: 0))
        assertWriterRejectsInvalidConfiguration(makeConfig(duration: .infinity))
    }

    func testWriterRejectsInvalidBitrateBeforeExport() {
        assertWriterRejectsInvalidConfiguration(makeConfig(averageBitRate: 0))
        assertWriterRejectsInvalidConfiguration(makeConfig(averageBitRate: 1_000_000_001))
    }

    func testWriterRejectsAlphaCodecForCompositedExport() {
        assertWriterRejectsInvalidConfiguration(makeConfig(codec: .hevcAlpha))
        assertWriterRejectsInvalidConfiguration(makeConfig(codec: .proRes4444))
    }

    func testWriterRejectsOverflowingFrameCountBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            makeConfig(framesPerSecond: .greatestFiniteMagnitude, duration: .greatestFiniteMagnitude)
        )
    }

    // MARK: - Trim and overlay correctness

    func testTrimExportSelectsSourceFramesAtStartTime() async throws {
        let sourceURL = temporaryMovieURL("composited-trim-luma-source")
        let outputURL = temporaryMovieURL("composited-trim-luma-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        // First half of the source is black, second half is white, so the decoded
        // luma of output frame 0 tells us which source frame the trim landed on.
        try makeTinySourceVideo(at: sourceURL, frameCount: 4) { index in
            index < 2 ? (0, 0, 0) : (255, 255, 255)
        }

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [TelemetrySample(elapsed: 0, distanceMeters: 0)]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                startTime: 1,
                duration: 0.5,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        let luma = try await firstFrameLuma(from: outputURL)
        XCTAssertGreaterThan(
            luma.mean,
            150,
            "Trim starting at 1s should land on the white source frames, not the leading black frames."
        )
    }

    func testExportBurnsOverlayOntoSourceFrames() async throws {
        let sourceURL = temporaryMovieURL("composited-overlay-source")
        let outputURL = temporaryMovieURL("composited-overlay-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        // Fully black source so any bright pixel in the output must come from the overlay.
        try makeTinySourceVideo(at: sourceURL, frameCount: 2) { _ in (0, 0, 0) }

        var element = OverlayElement.defaultElement(kind: .pace)
        element.frame = OverlayComponentFrame(x: 0.25, y: 0.4, scale: 1.6)
        element.customization.showsPanel = false
        element.customization.valueColor = OverlayColor(red: 1, green: 1, blue: 1)
        element.customization.labelColor = OverlayColor(red: 1, green: 1, blue: 1)

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
                TelemetrySample(elapsed: 1, distanceMeters: 3, speedMetersPerSecond: 3)
            ]),
            config: CompositedVideoWriterConfig(
                width: 128,
                height: 128,
                framesPerSecond: 2,
                duration: 0.5,
                averageBitRate: 400_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [element])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        let luma = try await firstFrameLuma(from: outputURL)
        XCTAssertGreaterThan(
            luma.max,
            120,
            "A black source with a white overlay must produce bright pixels once the overlay is composited."
        )
    }

    // MARK: - Audio passthrough

    func testAudioAndVideoShareOneTemporaryMovie() throws {
        let sourceURL = temporaryMovieURL("single-pass-source")
        let outputURL = temporaryMovieURL("single-pass-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }
        try makeTinySourceVideo(at: sourceURL, frameCount: 4, includeAudio: true)
        var maximumMovies = 0
        var events: [VideoExportDiagnosticEvent] = []
        let writer = CompositedVideoWriter(
            outputURL: outputURL, sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [TelemetrySample(elapsed: 0, distanceMeters: 0)]),
            config: CompositedVideoWriterConfig(
                width: 64, height: 64, framesPerSecond: 2, duration: 2,
                averageBitRate: 200_000, codec: .h264, overlayLayout: OverlayLayout(elements: []),
                diagnosticsHandler: { event in
                    events.append(event)
                    let files = (try? FileManager.default.contentsOfDirectory(
                        at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
                    let movies = files.filter {
                        $0.lastPathComponent.hasPrefix("DataLayerStudio-")
                            && $0.lastPathComponent.contains(outputURL.deletingPathExtension().lastPathComponent)
                    }
                    maximumMovies = max(maximumMovies, movies.count)
                }
            )
        )
        try writer.write()
        XCTAssertEqual(maximumMovies, 1, "Normal export must not keep a second full movie for audio muxing.")
        XCTAssertFalse(events.contains { [.audioMuxPassthrough, .audioMuxReencode].contains($0.stage) })
    }

    func testExportKeepsSourceAudioTrack() async throws {
        let sourceURL = temporaryMovieURL("composited-audio-source")
        let outputURL = temporaryMovieURL("composited-audio-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: sourceURL, frameCount: 4, includeAudio: true)

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0),
                TelemetrySample(elapsed: 2, distanceMeters: 6)
            ]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: 2,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let audioDuration = try await audioTracks[0].load(.timeRange).duration
        XCTAssertEqual(CMTimeGetSeconds(audioDuration), 2, accuracy: 0.15)
    }

    func testLongAudioVideoFixtureCompletesWithEveryFrame() async throws {
        let sourceURL = temporaryMovieURL("long-av-fixture")
        defer { Self.removeTemporaryFile(sourceURL) }
        try makeTinySourceVideo(at: sourceURL, frameCount: 600, framesPerSecond: 60, includeAudio: true) { _ in (40, 80, 120) }
        let frames = try await videoFrameSummary(from: sourceURL)
        XCTAssertEqual(frames.count, 600)
        let source = AVURLAsset(url: sourceURL)
        let duration = try await source.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), 10, accuracy: 0.01)
        let tracks = try await source.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let audioDuration = try await XCTUnwrap(tracks.first).load(.timeRange).duration
        XCTAssertEqual(CMTimeGetSeconds(audioDuration), 10, accuracy: 0.01)
    }

    func testFractionalTrimKeepsSoundPulseAlignedWithVideoAtNTSCFrameRate() async throws {
        let sourceURL = temporaryMovieURL("audio-pulse-source")
        let outputURL = temporaryMovieURL("audio-pulse-output")
        defer { [sourceURL, outputURL].forEach(Self.removeTemporaryFile) }
        try makeTinySourceVideo(at: sourceURL, frameCount: 120, framesPerSecond: 60,
                                includeAudio: true, audioPulseRange: 0.8..<1.4) { index in
            (0.8..<1.4).contains(Double(index) / 60) ? (220, 220, 220) : (0, 0, 0)
        }
        let config = CompositedVideoWriterConfig(
            width: 64, height: 64, framesPerSecond: 30_000.0 / 1_001,
            startTime: 0.35, duration: 1.5, averageBitRate: 200_000,
            codec: .h264, overlayLayout: OverlayLayout(elements: [])
        )
        try CompositedVideoWriter(outputURL: outputURL, sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: []), config: config).write()
        for (time, audible) in [(0.1, false), (0.65, true), (1.25, false)] {
            let audio = try await audioAmplitude(from: outputURL, at: time)
            let video = try await firstFrameLuma(from: outputURL, at: time).mean
            if audible {
                XCTAssertGreaterThan(audio, 3_000)
                XCTAssertGreaterThan(video, 150)
            } else {
                XCTAssertLessThan(audio, 100)
                XCTAssertLessThan(video, 10)
            }
        }
        let frames = try await videoFrameSummary(from: outputURL)
        XCTAssertEqual(frames.count, TransparentVideoFrameTiming(framesPerSecond: config.framesPerSecond, duration: config.duration).frameCount)
        let duration = try await AVURLAsset(url: outputURL).load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), 1.5015, accuracy: 0.025)
    }

    func testAudioReadFailureRecoversWithExistingMuxPath() async throws {
        let sourceURL = temporaryMovieURL("audio-recovery-source")
        let outputURL = temporaryMovieURL("audio-recovery-output")
        defer { [sourceURL, outputURL].forEach(Self.removeTemporaryFile) }
        try makeTinySourceVideo(at: sourceURL, frameCount: 4, includeAudio: true, audioPulseRange: 0..<2)
        var reads = 0
        var events: [VideoExportDiagnosticEvent] = []
        let writer = CompositedVideoWriter(outputURL: outputURL, sourceAsset: AVURLAsset(url: sourceURL),
            sourceDescription: "audio recovery fixture", config: CompositedVideoWriterConfig(
                width: 64, height: 64, framesPerSecond: 2, duration: 2, averageBitRate: 200_000,
                codec: .h264, diagnosticsHandler: { events.append($0) }),
            overlayStartTime: 0, renderOverlay: clearOverlay, audioSampleReader: { output in
                reads += 1
                if reads == 3 { throw NSError(domain: NSOSStatusErrorDomain, code: -50) }
                return output.copyNextSampleBuffer()
            })
        try writer.write()
        XCTAssertEqual(reads, 3)
        XCTAssertTrue(events.contains { $0.stage == .audioMuxPassthrough && $0.phase == .begin })
        let audio = try await audioAmplitude(from: outputURL, at: 0.5)
        XCTAssertGreaterThan(audio, 3_000)
        XCTAssertTrue(temporaryMovies(for: outputURL).isEmpty)
    }

    func testAudioDiskFailurePreservesExistingOutputWithoutRetry() throws {
        let sourceURL = temporaryMovieURL("audio-disk-source")
        let outputURL = temporaryMovieURL("audio-disk-output")
        defer { [sourceURL, outputURL].forEach(Self.removeTemporaryFile) }
        try makeTinySourceVideo(at: sourceURL, frameCount: 4, includeAudio: true)
        let original = Data("existing user movie".utf8)
        try original.write(to: outputURL)
        var events: [VideoExportDiagnosticEvent] = []
        let writer = CompositedVideoWriter(outputURL: outputURL, sourceAsset: AVURLAsset(url: sourceURL),
            sourceDescription: "disk failure fixture", config: CompositedVideoWriterConfig(
                width: 64, height: 64, framesPerSecond: 2, duration: 2, averageBitRate: 200_000,
                codec: .h264, diagnosticsHandler: { events.append($0) }),
            overlayStartTime: 0, renderOverlay: clearOverlay, audioSampleReader: { _ in
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            })
        XCTAssertThrowsError(try writer.write()) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, 28)
        }
        XCTAssertEqual(try Data(contentsOf: outputURL), original)
        XCTAssertFalse(events.contains { [.audioMuxPassthrough, .audioMuxReencode].contains($0.stage) })
        XCTAssertTrue(temporaryMovies(for: outputURL).isEmpty)
    }

    func testCancellationDuringAudioReadPreservesOutputAndCleansPartialMovie() throws {
        let sourceURL = temporaryMovieURL("audio-cancel-source")
        let outputURL = temporaryMovieURL("audio-cancel-output")
        defer { [sourceURL, outputURL].forEach(Self.removeTemporaryFile) }
        try makeTinySourceVideo(at: sourceURL, frameCount: 4, includeAudio: true)
        let original = Data("existing user movie".utf8)
        try original.write(to: outputURL)
        let lock = NSLock()
        var cancelled = false
        var reads = 0
        let writer = CompositedVideoWriter(outputURL: outputURL, sourceAsset: AVURLAsset(url: sourceURL),
            sourceDescription: "audio cancellation fixture", config: CompositedVideoWriterConfig(
                width: 64, height: 64, framesPerSecond: 2, duration: 2, averageBitRate: 200_000,
                codec: .h264, cancellationHandler: {
                    lock.lock(); defer { lock.unlock() }
                    return cancelled
                }),
            overlayStartTime: 0, renderOverlay: clearOverlay, audioSampleReader: { output in
                reads += 1
                if reads == 2 { lock.lock(); cancelled = true; lock.unlock() }
                return output.copyNextSampleBuffer()
            })
        XCTAssertThrowsError(try writer.write()) { error in
            guard case OverlayVideoError.cancelled = error else { return XCTFail("Expected cancellation, got \(error)") }
        }
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(try Data(contentsOf: outputURL), original)
        XCTAssertTrue(temporaryMovies(for: outputURL).isEmpty)
    }

    func testRenderFailureWithAudioReportsItsStageAndPreservesExistingOutput() throws {
        let sourceURL = temporaryMovieURL("audio-render-failure-source")
        let outputURL = temporaryMovieURL("audio-render-failure-output")
        defer { [sourceURL, outputURL].forEach(Self.removeTemporaryFile) }
        try makeTinySourceVideo(at: sourceURL, frameCount: 4, includeAudio: true)
        let original = Data("existing user movie".utf8)
        try original.write(to: outputURL)
        var events: [VideoExportDiagnosticEvent] = []
        let writer = CompositedVideoWriter(outputURL: outputURL, sourceAsset: AVURLAsset(url: sourceURL),
            sourceDescription: "render failure fixture", config: CompositedVideoWriterConfig(
                width: 64, height: 64, framesPerSecond: 2, duration: 2, averageBitRate: 200_000,
                codec: .h264, diagnosticsHandler: { events.append($0) }),
            overlayStartTime: 0, renderOverlay: { _, _ in throw NSError(domain: NSOSStatusErrorDomain, code: -50) })
        XCTAssertThrowsError(try writer.write())
        let failure = events.last { $0.phase == .failure && $0.stage != .exportFailed }
        XCTAssertEqual(failure?.stage, .renderOverlay)
        XCTAssertEqual(failure?.errorDomain, NSOSStatusErrorDomain)
        XCTAssertEqual(failure?.errorCode, -50)
        XCTAssertEqual(try Data(contentsOf: outputURL), original)
        XCTAssertTrue(temporaryMovies(for: outputURL).isEmpty)
    }

    func testTrimExportAlignsSourceAudioToStartTime() async throws {
        let sourceURL = temporaryMovieURL("composited-audio-trim-source")
        let outputURL = temporaryMovieURL("composited-audio-trim-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: sourceURL, frameCount: 4, includeAudio: true)

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0),
                TelemetrySample(elapsed: 2, distanceMeters: 6)
            ]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                startTime: 1,
                duration: 1,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let audioDuration = try await audioTracks[0].load(.timeRange).duration
        XCTAssertEqual(
            CMTimeGetSeconds(audioDuration),
            1,
            accuracy: 0.15,
            "A 1s window starting 1s into a 2s source must keep 1s of aligned audio."
        )
    }

    func testDownsamples60FPSVideoTo30FPSBySourceTimeAndKeepsAudio() async throws {
        try await assertResamplesSourceVideo(sourceFPS: 60, outputFPS: 30)
    }

    func testUpsamples30FPSVideoTo60FPSBySourceTimeAndKeepsAudio() async throws {
        try await assertResamplesSourceVideo(sourceFPS: 30, outputFPS: 60)
    }

    func testCancellationAfterLastRenderedFrameStopsFinalization() throws {
        let sourceURL = temporaryMovieURL("composited-cancel-source")
        let outputURL = temporaryMovieURL("composited-cancel-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }
        try makeTinySourceVideo(at: sourceURL, frameCount: 4, includeAudio: true)
        let lock = NSLock()
        var shouldCancel = false

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [TelemetrySample(elapsed: 0, distanceMeters: 0)]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: 2,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: []),
                progressHandler: { completed, total in
                    guard completed == total else { return }
                    lock.lock()
                    shouldCancel = true
                    lock.unlock()
                },
                cancellationHandler: {
                    lock.lock()
                    defer { lock.unlock() }
                    return shouldCancel
                }
            )
        )

        do {
            try writer.write()
            XCTFail("Expected cancellation")
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        } catch OverlayVideoError.cancelled {
            // Expected: cancellation arrived after rendering and interrupted finalization.
        } catch {
            XCTFail("Expected cancelled, got \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testPortrait5994FPSHEVCReportsTheFirstRenderedFrame() throws {
        let sourceURL = temporaryMovieURL("composited-progress-source")
        let outputURL = temporaryMovieURL("composited-progress-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }
        try makeTinySourceVideo(at: sourceURL, frameCount: 2)
        var progress: [(completed: Int, total: Int)] = []

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [TelemetrySample(elapsed: 0, distanceMeters: 0)]),
            config: CompositedVideoWriterConfig(
                width: 1_080,
                height: 1_920,
                framesPerSecond: 59.94,
                duration: 0.1,
                averageBitRate: 35_000_000,
                codec: .hevc,
                overlayLayout: OverlayLayout(elements: []),
                progressHandler: { completed, total in
                    progress.append((completed, total))
                }
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited HEVC encoder is unavailable on this Mac: \(error.description)")
        }

        let first = try XCTUnwrap(progress.first)
        XCTAssertEqual(first.completed, 1)
        XCTAssertGreaterThan(first.total, first.completed)
    }

    func testRenderCompletionWaitCancelsAReaderBlockingTheRenderQueue() {
        let finished = DispatchSemaphore(value: 0)
        let blockedRead = DispatchSemaphore(value: 0)
        let renderQueue = DispatchQueue(label: "com.datalayer.tests.stalled-render")
        let queueKey = DispatchSpecificKey<Bool>()
        renderQueue.setSpecific(key: queueKey, value: true)
        renderQueue.async {
            blockedRead.wait()
            finished.signal()
        }
        var cancellationCallCount = 0
        var cancelledOutsideRenderQueue = false
        let startedAt = ProcessInfo.processInfo.systemUptime

        VideoExportSupport.waitForRenderCompletion(
            finished,
            pollInterval: .milliseconds(1),
            cancellationHandler: { true },
            cancelProducer: {
                cancellationCallCount += 1
                cancelledOutsideRenderQueue = DispatchQueue.getSpecific(key: queueKey) == nil
                blockedRead.signal()
            }
        )

        XCTAssertEqual(cancellationCallCount, 1)
        XCTAssertTrue(cancelledOutsideRenderQueue)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, 1)
    }

    func testRenderCompletionWaitDoesNotCancelAProducerThatFinishesNormally() {
        let finished = DispatchSemaphore(value: 0)
        let renderQueue = DispatchQueue(label: "com.datalayer.tests.finishing-render")
        var didCancelProducer = false
        renderQueue.asyncAfter(deadline: .now() + .milliseconds(10)) {
            finished.signal()
        }

        VideoExportSupport.waitForRenderCompletion(
            finished,
            pollInterval: .milliseconds(1),
            cancellationHandler: { false },
            cancelProducer: {
                didCancelProducer = true
            }
        )

        XCTAssertFalse(didCancelProducer)
    }

    // MARK: - Helpers

    private func assertResamplesSourceVideo(
        sourceFPS: Int32,
        outputFPS: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let sourceURL = temporaryMovieURL("composited-resample-\(sourceFPS)-source")
        let outputURL = temporaryMovieURL("composited-resample-\(Int(outputFPS))-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }
        try makeTinySourceVideo(
            at: sourceURL,
            frameCount: Int(sourceFPS),
            framesPerSecond: sourceFPS,
            includeAudio: true
        ) { index in
            index < Int(sourceFPS) / 2 ? (0, 0, 0) : (255, 255, 255)
        }

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [TelemetrySample(elapsed: 0, distanceMeters: 0)]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: outputFPS,
                duration: 1,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        let video = try await videoFrameSummary(from: outputURL)
        XCTAssertEqual(video.count, Int(outputFPS), file: file, line: line)
        XCTAssertGreaterThan(video.lastMeanLuma, 180, file: file, line: line)

        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioTrack = try XCTUnwrap(
            audioTracks.first,
            file: file,
            line: line
        )
        let audioDuration = try await audioTrack.load(.timeRange).duration
        XCTAssertEqual(CMTimeGetSeconds(audioDuration), 1, accuracy: 0.15, file: file, line: line)
    }

    private func makeConfig(
        width: Int = 64,
        height: Int = 64,
        framesPerSecond: Double = 2,
        startTime: TimeInterval = 0,
        duration: TimeInterval = 1,
        averageBitRate: Int = 200_000,
        codec: OverlayVideoCodec = .h264
    ) -> CompositedVideoWriterConfig {
        CompositedVideoWriterConfig(
            width: width,
            height: height,
            framesPerSecond: framesPerSecond,
            startTime: startTime,
            duration: duration,
            averageBitRate: averageBitRate,
            codec: codec,
            overlayLayout: OverlayLayout(elements: [])
        )
    }

    private func assertWriterRejectsInvalidConfiguration(
        _ config: CompositedVideoWriterConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Point at a real (existing) output directory so the dedicated validation
        // rule fails first, not the output-URL existence check. The source video
        // is never read because validation runs before any file access.
        let outputURL = temporaryMovieURL("composited-invalid")
        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: temporaryMovieURL("composited-missing-source"),
            series: TelemetrySeries(samples: []),
            config: config
        )

        XCTAssertThrowsError(try writer.write(), file: file, line: line) { error in
            guard case OverlayVideoError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)", file: file, line: line)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path), file: file, line: line)
    }

    private func temporaryMovieURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
            .appendingPathExtension("mov")
    }

    private func firstFrameLuma(from url: URL, at seconds: TimeInterval = 0) async throws -> (max: Double, mean: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        if seconds > 0 {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: seconds, preferredTimescale: 600_000),
                                          duration: CMTime(seconds: 0.1, preferredTimescale: 600_000))
        }
        let output = AVAssetReaderTrackOutput(
            track: try XCTUnwrap(tracks.first),
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let sampleBuffer = try XCTUnwrap(output.copyNextSampleBuffer())
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)

        var maxLuma = 0.0
        var sumLuma = 0.0
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                let offset = rowStart + x * 4
                let blue = Double(bytes[offset])
                let green = Double(bytes[offset + 1])
                let red = Double(bytes[offset + 2])
                let luma = 0.299 * red + 0.587 * green + 0.114 * blue
                maxLuma = max(maxLuma, luma)
                sumLuma += luma
            }
        }
        return (maxLuma, sumLuma / Double(width * height))
    }

    private func videoFrameSummary(from url: URL) async throws -> (count: Int, lastMeanLuma: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: try XCTUnwrap(tracks.first),
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var count = 0
        var lastMeanLuma = 0.0
        while let sampleBuffer = output.copyNextSampleBuffer(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
                .assumingMemoryBound(to: UInt8.self)
            var sum = 0.0
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    sum += 0.114 * Double(bytes[offset])
                        + 0.587 * Double(bytes[offset + 1])
                        + 0.299 * Double(bytes[offset + 2])
                }
            }
            count += 1
            lastMeanLuma = sum / Double(width * height)
        }
        return (count, lastMeanLuma)
    }

    private static func removeTemporaryFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func makeTinySourceVideo(
        at url: URL,
        frameCount: Int = 2,
        framesPerSecond: Int32 = 2,
        includeAudio: Bool = false,
        audioPulseRange: Range<Double>? = nil,
        frameColor: (Int) -> (red: UInt8, green: UInt8, blue: UInt8) = { index in
            (UInt8(80 + index * 40), 120, 160)
        }
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(input) else {
            throw OverlayVideoError.unsupportedEncoder("Could not create tiny source video input.")
        }
        writer.add(input)

        let sampleRate = 44_100.0
        let totalDuration = Double(frameCount) / Double(framesPerSecond)
        var audioInput: AVAssetWriterInput?
        if includeAudio {
            let newInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            newInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(newInput) else {
                throw OverlayVideoError.unsupportedEncoder("Could not create tiny source audio input.")
            }
            writer.add(newInput)
            audioInput = newInput
        }

        guard writer.startWriting() else {
            throw OverlayVideoError.cannotStartWriter(writer.error?.localizedDescription ?? "Could not start tiny source writer.")
        }
        writer.startSession(atSourceTime: .zero)

        // Finish the tiny PCM track before video buffering can wait for missing audio.
        if let audioInput {
            let sampleBuffer = try makeSilentAudioSampleBuffer(durationSeconds: totalDuration, sampleRate: sampleRate, pulseRange: audioPulseRange)
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while !audioInput.isReadyForMoreMediaData {
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Tiny source audio input stalled.")
                }
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard audioInput.append(sampleBuffer) else {
                throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Could not append tiny source audio.")
            }
            audioInput.markAsFinished()
        }

        for frameIndex in 0..<frameCount {
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    throw OverlayVideoError.writerFailed(writer.error?.localizedDescription
                        ?? "Tiny source video stalled at frame \(frameIndex)/\(frameCount), writer status \(writer.status.rawValue).")
                }
                Thread.sleep(forTimeInterval: 0.001)
            }
            let color = frameColor(frameIndex)
            let buffer = try makePixelBuffer(red: color.red, green: color.green, blue: color.blue)
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Could not append tiny source frame.")
            }
        }
        input.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 10) == .success else {
            throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Tiny source writer did not finish within 10 seconds.")
        }

        guard writer.status == .completed else {
            throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Tiny source writer failed.")
        }
    }

    private func makeSilentAudioSampleBuffer(durationSeconds: Double, sampleRate: Double, pulseRange: Range<Double>? = nil) throws -> CMSampleBuffer {
        let sampleCount = Int(sampleRate * durationSeconds)
        let bytesPerSample = 2
        let dataSize = sampleCount * bytesPerSample

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerSample),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerSample),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else {
            throw OverlayVideoError.writerFailed("Could not create tiny source audio format description.")
        }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer else {
            throw OverlayVideoError.writerFailed("Could not allocate tiny source audio block buffer.")
        }
        guard CMBlockBufferFillDataBytes(
            with: 0,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: dataSize
        ) == noErr else {
            throw OverlayVideoError.writerFailed("Could not zero-fill tiny source audio block buffer.")
        }
        if let pulseRange {
            let samples: [Int16] = (0..<sampleCount).map { index in
                let time = Double(index) / sampleRate
                return pulseRange.contains(time) ? Int16(12_000 * sin(2 * .pi * 440 * time)) : 0
            }
            let status = samples.withUnsafeBytes {
                CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: blockBuffer,
                                              offsetIntoDestination: 0, dataLength: dataSize)
            }
            XCTAssertEqual(status, noErr)
        }

        var sampleBuffer: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: sampleCount,
            presentationTimeStamp: .zero,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else {
            throw OverlayVideoError.writerFailed("Could not create tiny source audio sample buffer.")
        }
        return sampleBuffer
    }

    private func audioAmplitude(from url: URL, at seconds: TimeInterval) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { return 0 }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: seconds, preferredTimescale: 44_100),
            duration: CMTime(seconds: 0.1, preferredTimescale: 44_100)
        )
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var sampleTotal = 0.0
        var sampleCount = 0
        while let sampleBuffer = output.copyNextSampleBuffer(),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            let byteCount = CMBlockBufferGetDataLength(blockBuffer)
            var bytes = [UInt8](repeating: 0, count: byteCount)
            let copyStatus = bytes.withUnsafeMutableBytes { rawBuffer in
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: byteCount,
                    destination: rawBuffer.baseAddress!
                )
            }
            XCTAssertEqual(copyStatus, noErr)
            for index in stride(from: 0, to: byteCount - 1, by: 2) {
                let bits = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
                sampleTotal += abs(Double(Int16(bitPattern: bits)))
                sampleCount += 1
            }
        }
        return sampleCount > 0 ? sampleTotal / Double(sampleCount) : 0
    }

    private func clearOverlay(_ time: TimeInterval, _ buffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
    }

    private func temporaryMovies(for output: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory,
                                                       includingPropertiesForKeys: nil)) ?? []).filter {
            $0.lastPathComponent.hasPrefix("DataLayerStudio-")
                && $0.lastPathComponent.contains(output.deletingPathExtension().lastPathComponent)
        }
    }

    private func makePixelBuffer(red: UInt8, green: UInt8, blue: UInt8) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)
        for y in 0..<64 {
            for x in 0..<64 {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = blue
                bytes[offset + 1] = green
                bytes[offset + 2] = red
                bytes[offset + 3] = 255
            }
        }
        return pixelBuffer
    }
}

private final class FailedDecodeAttempt: TimelineSegmentDecodeAttempt {
    var reader: AVAssetReader? { nil }
    var status: AVAssetReader.Status { .failed }
    var error: Error? { nil }

    func copyNextSampleBuffer() -> CMSampleBuffer? { nil }
    func cancel() {}
}

private extension OverlayVideoError {
    var isUnavailableCompositedTestEncoder: Bool {
        switch self {
        case .unsupportedEncoder, .cannotStartWriter:
            return true
        case let .writerFailed(message, _):
            return message.localizedCaseInsensitiveContains("encoder") || message.contains("-12903")
        case .unreadableVideo,
             .cannotCreatePixelBuffer,
             .cannotCreateBitmapContext,
             .invalidConfiguration,
             .cancelled:
            return false
        }
    }
}
