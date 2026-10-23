#if os(macOS)
import AVFoundation
import Darwin
@testable import OverlayCore
import XCTest

final class VideoExportWorkerTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private var worker: URL { root.appendingPathComponent(".build/debug/datalayer-video-worker") }

    func testTelemetryTransferPreservesNormalizedSamplesAndPausesExactly() throws {
        let series = TelemetrySeries(samples: [
            .init(elapsed: 0, altitudeMeters: 100, distanceMeters: 0, speedMetersPerSecond: 3),
            .init(elapsed: 10, altitudeMeters: 102, distanceMeters: 30, speedMetersPerSecond: 3)
        ], pausedRanges: [.init(start: 3, duration: 2)])
        let decoded = try PropertyListDecoder().decode(TelemetrySeries.self, from: PropertyListEncoder().encode(series))
        XCTAssertEqual(decoded, series, "IPC must not run normalization or smoothing twice")
    }

    func testCustomTemporaryDirectoryUsedByNormalAndAlphaWorkersAndCleaned() throws {
        try requireWorker()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scratch = folder.appendingPathComponent("external-scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        let (project, telemetry, base) = overlayProject()
        let output = folder.appendingPathComponent("result.mov")
        let systemBefore = try stagingDirectories()
        for codec in [OverlayVideoCodec.h264, .hevcAlpha, .proRes4444] {
            var config = base
            config.codec = codec
            config.temporaryDirectory = scratch
            var sawCustomStaging = false
            config.diagnosticsHandler = { _ in
                if let children = try? FileManager.default.contentsOfDirectory(atPath: scratch.path),
                   children.contains(where: { $0.contains("-worker-") }) { sawCustomStaging = true }
            }
            _ = try VideoExportWorker.write(outputURL: output, project: project, telemetry: telemetry,
                                           config: config, executableURL: worker)
            XCTAssertTrue(sawCustomStaging)
            let frames = try decode(output)
            XCTAssertEqual(frames.count, 3)
            if codec.exportMode == .overlay { XCTAssertTrue(frames.allSatisfy { $0.maxAlpha <= 1 }) }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [])
            XCTAssertEqual(try stagingDirectories(), systemBefore)
        }
        // Runtime authorization paths must never leak into project/worker config persistence.
        var config = base
        config.temporaryDirectory = scratch
        let restored = try PropertyListDecoder().decode(TimelineVideoWriterConfig.self, from: PropertyListEncoder().encode(config))
        XCTAssertNil(restored.temporaryDirectory)
    }

    func testMissingCustomTemporaryDirectoryFailsBeforeWorkerLaunchAndPreservesOutput() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (project, telemetry, base) = overlayProject()
        var config = base
        config.temporaryDirectory = folder.appendingPathComponent("unplugged-drive")
        let output = folder.appendingPathComponent("existing.mov")
        let original = Data("existing output".utf8)
        try original.write(to: output)
        let before = try stagingDirectories()
        XCTAssertThrowsError(try VideoExportWorker.write(outputURL: output, project: project, telemetry: telemetry,
                                                       config: config, executableURL: worker))
        XCTAssertEqual(try Data(contentsOf: output), original)
        XCTAssertEqual(try stagingDirectories(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.temporaryDirectory!.path))
    }

    func testCustomDirectoryAlsoUsedWithoutHelper() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let previous = VideoExportWorker.executableURL
        VideoExportWorker.executableURL = nil
        defer { VideoExportWorker.executableURL = previous }
        let (project, telemetry, base) = overlayProject()
        let scratch = folder.appendingPathComponent("scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        for codec in [OverlayVideoCodec.h264, .hevcAlpha, .proRes4444] {
            var config = base
            config.codec = codec
            config.temporaryDirectory = scratch
            var sawTemporaryMovie = false
            config.progressHandler = { _, _ in
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: scratch.path),
                   contents.contains(where: { $0.hasSuffix(".mov") }) { sawTemporaryMovie = true }
            }
            let output = folder.appendingPathComponent("out.mov")
            _ = try TimelineVideoWriter(outputURL: output, project: project, telemetrySeriesByAssetID: telemetry, config: config).write()
            XCTAssertTrue(sawTemporaryMovie)
            XCTAssertEqual(try decode(output).count, 3)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [])
        }
    }

    func testOrphanWorkerExitsEvenWhileWaitingForInput() throws {
        try requireWorker()
        let process = Process()
        let input = Pipe()
        process.executableURL = worker
        process.arguments = ["--video-worker", "1"] // The expected parent is already gone.
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { VideoExportWorker.stop(process); try? input.fileHandleForWriting.close() }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(process.terminationStatus, 1)
    }

    func testFallbackIsBoundedPreservesCodecAndRejectsDiskErrorsAndAlpha() {
        var config = TimelineVideoWriterConfig(width: 1920, height: 1080, framesPerSecond: 29.97,
                                              duration: 20, codec: .hevc)
        let read = VideoExportDiagnosticEvent(stage: .readSource, phase: .failure)
        let encode = VideoExportDiagnosticEvent(stage: .finishWriter, phase: .failure)
        let error = VideoExportWaitError.stalled
        XCTAssertNil(VideoExportWorker.fallback(config: config, error: OverlayVideoError.cancelled, event: encode))
        XCTAssertNil(VideoExportWorker.fallback(config: config, error: VideoExportWaitError.cleanupPending, event: read))
        config = VideoExportWorker.fallback(config: config, error: error, event: read)!
        XCTAssertTrue(config.softwareDecoding)
        XCTAssertFalse(config.softwareEncoding)
        XCTAssertNil(VideoExportWorker.fallback(config: config, error: error, event: read))
        config = VideoExportWorker.fallback(config: config, error: error, event: encode)!
        XCTAssertTrue(config.softwareEncoding)
        XCTAssertEqual(config.codec, .hevc)
        XCTAssertEqual(config.width, 1920)
        XCTAssertEqual(config.framesPerSecond, 29.97)
        XCTAssertNil(VideoExportWorker.fallback(config: config, error: error, event: encode))
        config.softwareEncoding = false
        let disk = OverlayVideoError.writerFailed("disk full", underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)))
        XCTAssertNil(VideoExportWorker.fallback(config: config, error: disk, event: encode))
        for codec in [OverlayVideoCodec.hevcAlpha, .proRes4444] {
            config.codec = codec
            XCTAssertNil(VideoExportWorker.fallback(config: config, error: error, event: encode))
        }
    }

    func testStalledProcessIsKilledBeforeSoftwareRetryAndAllStagingIsRemoved() throws {
        try requireWorker()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("old-pid")
        let executable = folder.appendingPathComponent("worker")
        let event = VideoExportWorker.Message(event: .init(stage: .readSource, phase: .begin))
        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        // First child ignores SIGTERM like a stuck native call; the second execs the real helper.
        let script = """
        #!/bin/sh
        if [ ! -f '\(marker.path)' ]; then
          echo $$ > '\(marker.path)'
          trap '' TERM
          printf '%s\\n' '\(json)'
          while :; do :; done
        fi
        if kill -0 "$(cat '\(marker.path)')" 2>/dev/null; then exit 91; fi
        exec '\(worker.path)' "$@"
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let before = try stagingDirectories()
        let (project, telemetry, config) = overlayProject()
        let output = folder.appendingPathComponent("result.mov")
        try Data("old export".utf8).write(to: output)
        let result = try VideoExportWorker.write(outputURL: output, project: project, telemetry: telemetry,
                                               config: config, executableURL: executable, stallTimeout: 2)
        XCTAssertTrue(result.warnings.isEmpty)
        let pid = try XCTUnwrap(Int32(String(contentsOf: marker).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        XCTAssertEqual(try stagingDirectories(), before)
        XCTAssertEqual(try decode(output).count, 3)
    }

    func testCancellationKillsWorkerPreservesDestinationAndAllowsNextExport() throws {
        try requireWorker()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let executable = folder.appendingPathComponent("worker")
        let marker = folder.appendingPathComponent("pid")
        try "#!/bin/sh\necho $$ > '\(marker.path)'\ntrap '' TERM\nwhile :; do :; done\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var (project, telemetry, base) = overlayProject()
        let scratch = folder.appendingPathComponent("custom-scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        base.temporaryDirectory = scratch
        var config = base
        config.cancellationHandler = { FileManager.default.fileExists(atPath: marker.path) }
        let output = folder.appendingPathComponent("result.mov")
        let original = Data("existing output must survive".utf8)
        try original.write(to: output)
        let before = try stagingDirectories()
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try VideoExportWorker.write(outputURL: output, project: project, telemetry: telemetry,
                                                        config: config, executableURL: executable)) {
            guard case OverlayVideoError.cancelled = $0 else { return XCTFail("Expected cancellation, got \($0)") }
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 3)
        XCTAssertEqual(try Data(contentsOf: output), original)
        XCTAssertEqual(try stagingDirectories(), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [])
        _ = try VideoExportWorker.write(outputURL: output, project: project, telemetry: telemetry,
                                       config: base, executableURL: worker)
        XCTAssertEqual(try decode(output).count, 3)
    }

    func testReportedEncoderFailureRetriesAfterGenericExportFailureEvent() throws {
        try requireWorker()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("failed")
        let executable = folder.appendingPathComponent("worker")
        let failure = VideoExportWorker.Failure(OverlayVideoError.cannotStartWriter("encoder unavailable"))
        let messages: [VideoExportWorker.Message] = [
            .init(event: .init(stage: .prepareWriter, phase: .begin)),
            .init(event: .init(stage: .exportFailed, phase: .failure)),
            .init(failure: failure)
        ]
        let lines = try messages.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }.joined(separator: "\n")
        try """
        #!/bin/sh
        if [ ! -f '\(marker.path)' ]; then
          touch '\(marker.path)'
          printf '%s\\n' '\(lines)'
          exit 1
        fi
        exec '\(worker.path)' "$@"
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let (project, telemetry, config) = overlayProject()
        let output = folder.appendingPathComponent("result.mov")
        _ = try VideoExportWorker.write(outputURL: output, project: project, telemetry: telemetry,
                                       config: config, executableURL: executable)
        XCTAssertEqual(try decode(output).count, 3)
    }

    func testWorkerPreservesTransparentPixels() throws {
        try requireWorker()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("alpha.mov")
        for codec in [OverlayVideoCodec.proRes4444, .hevcAlpha] {
            try VideoExportWorker.writeOverlay(outputURL: output,
                series: TelemetrySeries(samples: [.init(elapsed: 0, speedMetersPerSecond: 3)]),
                config: .init(width: 128, height: 128, framesPerSecond: 2, duration: 1, codec: codec,
                              overlayLayout: .init(elements: [])), executableURL: worker)
            let frames = try decode(output)
            XCTAssertEqual(frames.count, 2)
            XCTAssertTrue(frames.allSatisfy { $0.maxAlpha <= 1 })
        }
    }

    func testWorkerDoesNotOpenUnusedVideoAssets() throws {
        try requireWorker()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (project, telemetry, config) = overlayProject()
        project.assets.append(.init(id: "missing", kind: .video, url: URL(fileURLWithPath: "/missing.mov"),
                                    displayName: "missing", duration: 1))
        project.tracks.append(.init(id: "off", kind: .video, name: "Disabled", isEnabled: false, clips: [
            .init(id: "unused", assetID: "missing", timelineStart: 0, duration: 1)
        ]))
        let output = folder.appendingPathComponent("out.mov")
        _ = try VideoExportWorker.write(outputURL: output, project: project, telemetry: telemetry,
                                       config: config, executableURL: worker)
        XCTAssertEqual(try decode(output).count, 3)
        project.tracks[1].isEnabled = true
        let result = try VideoExportWorker.write(outputURL: output, project: project, telemetry: telemetry,
                                                config: config, executableURL: worker)
        XCTAssertTrue(result.warnings.contains { $0.kind == .videoSegmentSkipped && $0.clipID == "unused" })
        XCTAssertEqual(try decode(output).count, 3)
    }

    func testActualMixedSourcesThroughHardwareAndSoftwareWorkers() throws {
        guard let path = ProcessInfo.processInfo.environment["DLS_EXPORT_REAL_MEDIA_DIR"] else {
            throw XCTSkip("Set DLS_EXPORT_REAL_MEDIA_DIR to run local camera/FIT acceptance")
        }
        try requireWorker()
        let media = URL(fileURLWithPath: path)
        let outputFolder = root.appendingPathComponent(".build/video-worker-validation")
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        let files = ["multi/1.mov", "multi/2.mov", "multi/3.mov", "1kmrun.mov"]
        let assets = try files.enumerated().map { index, file in
            let url = media.appendingPathComponent(file)
            return MediaAsset(id: String(index), kind: .video, url: url, displayName: file,
                              duration: try VideoMetadata.load(from: url).duration)
        }
        let activityURL = media.appendingPathComponent("multi/478791068148596942.fit")
        let series = try TelemetryFileParser().parse(url: activityURL)
        let activity = MediaAsset(id: "fit", kind: .activity, url: activityURL, displayName: "Activity", duration: series.duration)
        let project = TimelineProject(outputWidth: 1920, outputHeight: 1080, framesPerSecond: 29.97,
            distanceUnit: .kilometers, assets: assets + [activity], tracks: [
                .init(id: "v", kind: .video, name: "Video", clips: assets.enumerated().map { index, asset in
                    .init(id: "c\(index)", assetID: asset.id, timelineStart: Double(index) * 4, duration: 4, sourceIn: 1)
                }),
                .init(id: "o", kind: .overlay, name: "Overlay", clips: [
                    .init(id: "fit-clip", assetID: "fit", timelineStart: 0, duration: 16, layout: .default)
                ])
            ])
        for mode in ["hardware-h264", "software-h264", "software-hevc"] {
            var config = TimelineVideoWriterConfig(width: 1920, height: 1080, framesPerSecond: 29.97,
                                                  duration: 16, codec: mode.hasSuffix("hevc") ? .hevc : .h264)
            config.softwareDecoding = mode.hasPrefix("software")
            config.softwareEncoding = mode.hasPrefix("software")
            let output = outputFolder.appendingPathComponent("\(mode).mov")
            let result = try VideoExportWorker.write(outputURL: output, project: project, telemetry: ["fit": series],
                                                   config: config, executableURL: worker)
            XCTAssertTrue(result.warnings.isEmpty, "\(mode): \(result.warnings)")
            let frames = try decode(output)
            XCTAssertEqual(frames.count, 480, mode)
            for index in [0, 119, 120, 239, 240, 359, 360, 479] {
                XCTAssertGreaterThan(frames[index].maxRGB, 30, "\(mode) frame \(index) is black")
            }
            let asset = AVURLAsset(url: output)
            XCTAssertFalse(asset.tracks(withMediaType: .audio).isEmpty, mode)
            XCTAssertEqual(CMTimeGetSeconds(asset.duration), 16.016, accuracy: 0.04)
        }
    }

    private func requireWorker() throws {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: worker.path), "Build datalayer-video-worker first")
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func stagingDirectories() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("DataLayerStudio-\(getpid())-worker-") })
    }

    private func overlayProject() -> (TimelineProject, [String: TelemetrySeries], TimelineVideoWriterConfig) {
        let series = TelemetrySeries(samples: [.init(elapsed: 0, speedMetersPerSecond: 3)])
        let activity = MediaAsset(id: "a", kind: .activity, url: URL(fileURLWithPath: "/unused.fit"), displayName: "Activity", duration: 1)
        let project = TimelineProject(outputWidth: 64, outputHeight: 64, framesPerSecond: 3, distanceUnit: .kilometers,
            assets: [activity], tracks: [.init(id: "o", kind: .overlay, name: "O", clips: [
                .init(id: "c", assetID: "a", timelineStart: 0, duration: 1, layout: .init(elements: []))
            ])])
        return (project, ["a": series], .init(width: 64, height: 64, framesPerSecond: 3, duration: 1, codec: .h264))
    }

    private func decode(_ url: URL) throws -> [(maxRGB: UInt8, maxAlpha: UInt8)] {
        let asset = AVURLAsset(url: url)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var values: [(UInt8, UInt8)] = []
        while let sample = output.copyNextSampleBuffer() {
            let pixel = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            CVPixelBufferLockBaseAddress(pixel, .readOnly)
            let data = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixel)
            var rgb: UInt8 = 0; var alpha: UInt8 = 0
            // Sample the source area away from telemetry along with alpha across the canvas.
            for y in stride(from: 0, to: CVPixelBufferGetHeight(pixel), by: 16) {
                for x in stride(from: 0, to: CVPixelBufferGetWidth(pixel), by: 16) {
                    let offset = y * rowBytes + x * 4
                    rgb = max(rgb, data[offset], data[offset + 1], data[offset + 2])
                    alpha = max(alpha, data[offset + 3])
                }
            }
            CVPixelBufferUnlockBaseAddress(pixel, .readOnly)
            values.append((rgb, alpha))
        }
        XCTAssertEqual(reader.status, .completed, "\(String(describing: reader.error))")
        return values
    }
}
#endif
