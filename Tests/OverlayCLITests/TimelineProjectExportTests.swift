import AVFoundation
import CoreVideo
import OverlayCore
import XCTest
@testable import overlay

final class TimelineProjectExportTests: XCTestCase {
    func testSavedExportSettingsAndRangeAreInherited() throws {
        let project = makeProject()
        let options = try options().resolvingTimelineExportSettings(project)
        XCTAssertEqual(options.exportMode, .video)
        XCTAssertEqual(options.codec, .h264)
        XCTAssertEqual(options.averageBitRate, 650_000)
        XCTAssertEqual(options.activityTrim, ActivityTrim(startSeconds: 1, endSeconds: 3))
        let request = timelineExportRequest(project: project, options: options)
        XCTAssertEqual(request.timelineStart, 1)
        XCTAssertEqual(request.duration, 2)
        XCTAssertEqual(request.width, 320)
        XCTAssertEqual(request.height, 180)
        XCTAssertEqual(request.framesPerSecond, 4)
    }

    func testExplicitOptionsOverrideOnlyTheirSavedFields() throws {
        let project = makeProject()
        let options = try options([
            "--export-mode", "overlay", "--bitrate", "1000", "--activity-trim-start", "0",
            "--width", "640", "--time-zone", "UTC"
        ]).resolvingTimelineExportSettings(project)
        XCTAssertEqual(options.exportMode, .overlay)
        XCTAssertEqual(options.codec, .hevcAlpha)
        XCTAssertEqual(options.averageBitRate, 1_000_000)
        XCTAssertEqual(options.activityTrim, ActivityTrim(startSeconds: 0, endSeconds: 3))
        XCTAssertEqual(timelineExportRequest(project: project, options: options).width, 640)
        XCTAssertEqual(options.timeZoneOverride?.rawValue, "UTC")

        let codecOnly = try self.options(["--codec", "hevc", "--bitrate-bps", "500123"])
            .resolvingTimelineExportSettings(project)
        XCTAssertEqual(codecOnly.exportMode, .video)
        XCTAssertEqual(codecOnly.codec, .hevc)
        XCTAssertEqual(codecOnly.averageBitRate, 500_123)
        XCTAssertThrowsError(try self.options(["--codec", "hevc-alpha"]).resolvingTimelineExportSettings(project))
        XCTAssertThrowsError(try self.options(["--activity-trim-start", "4"]).resolvingTimelineExportSettings(project))
    }

    func testLegacyProjectKeepsCLIDefaultsAndInvalidSavedCodecIsNormalized() throws {
        var project = makeProject()
        project.exportSettings = nil
        let legacy = try options().resolvingTimelineExportSettings(project)
        XCTAssertEqual(legacy.exportMode, .overlay)
        XCTAssertEqual(legacy.codec, .hevcAlpha)
        XCTAssertEqual(legacy.averageBitRate, 12_000_000)
        XCTAssertEqual(legacy.activityTrim, .none)
        XCTAssertEqual(timelineExportRequest(project: project, options: legacy).duration, 4)

        project.exportSettings = TimelineProjectExportSettings(exportMode: .video, codec: .hevcAlpha, bitRateKbps: Int.max)
        let normalized = try options().resolvingTimelineExportSettings(project)
        XCTAssertEqual(normalized.codec, .hevc)
        XCTAssertEqual(normalized.averageBitRate, 1_000_000_000)
    }

    func testMovedProjectRestoresRelativePathsAndReadableBookmarks() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let media = directory.appendingPathComponent("activity.gpx")
        try Data(gpx.utf8).write(to: media)
        let projectURL = directory.appendingPathComponent("project.dlsproj")
        var project = makeProject()
        project.assets[0].url = directory.appendingPathComponent("missing.gpx")
        project.assets[0].relativePath = media.lastPathComponent
        project.assets[0].bookmarkData = Data([1, 2, 3])
        try JSONEncoder().encode(project).write(to: projectURL)
        let relative = try loadTimelineProject(from: projectURL)
        XCTAssertEqual(relative.assets[0].url, media)
        XCTAssertEqual(relative.tracks, project.tracks)

        project.assets[0].bookmarkData = try media.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        project.assets[0].relativePath = nil
        try JSONEncoder().encode(project).write(to: projectURL)
        XCTAssertEqual(try loadTimelineProject(from: projectURL).assets[0].url.standardizedFileURL, media.standardizedFileURL)
    }

    func testMissingMediaAndFutureProjectRemainErrors() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let projectURL = directory.appendingPathComponent("project.dlsproj")
        var project = makeProject()
        project.assets[0].url = directory.appendingPathComponent("missing.gpx")
        try JSONEncoder().encode(project).write(to: projectURL)
        XCTAssertThrowsError(try renderTimelineProject(options: options(["--inspect"]), projectURL: projectURL))
        project.schemaVersion = TimelineProject.currentSchemaVersion + 1
        try JSONEncoder().encode(project).write(to: projectURL)
        XCTAssertThrowsError(try loadTimelineProject(from: projectURL))
    }

    func testIndividualOutputsAreAllCheckedBeforeWriting() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let media = directory.appendingPathComponent("activity.gpx")
        try Data(gpx.utf8).write(to: media)
        var project = makeProject()
        project.assets[0].url = media
        project.exportSettings?.exportMode = .overlay
        project.exportSettings?.codec = .hevcAlpha
        project.exportSettings?.renderScope = .individualClips
        project.tracks[0].clips = [
            TimelineClip(id: "one", assetID: "activity", timelineStart: 0, duration: 2),
            TimelineClip(id: "two", assetID: "activity", timelineStart: 2, duration: 2, sourceIn: 2)
        ]
        let projectURL = directory.appendingPathComponent("project.dlsproj")
        try JSONEncoder().encode(project).write(to: projectURL)
        let output = directory.appendingPathComponent("output.mov")
        let first = directory.appendingPathComponent("output_01.mov")
        let second = directory.appendingPathComponent("output_02.mov")
        let sentinel = Data("keep existing file".utf8)
        try sentinel.write(to: second)
        let options = try self.options(["--output", output.path])
        XCTAssertThrowsError(try renderTimelineProject(options: options, projectURL: projectURL)) { error in
            guard case CLIError.outputAlreadyExists(second.path) = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertEqual(try Data(contentsOf: second), sentinel)

        // --force still cannot overwrite a relocated input through a numbered output.
        try Data(gpx.utf8).write(to: second)
        try FileManager.default.removeItem(at: media)
        try FileManager.default.createSymbolicLink(at: media, withDestinationURL: second)
        try JSONEncoder().encode(project).write(to: projectURL)
        XCTAssertThrowsError(try renderTimelineProject(options: self.options(["--output", output.path, "--force"]), projectURL: projectURL)) { error in
            guard case CLIError.outputMatchesInput(second.path) = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
    }

    func testEncodedCLIProjectMatchesGUIWriterSettingsWeatherAndTrim() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let media = directory.appendingPathComponent("activity.gpx")
        try Data(gpx.utf8).write(to: media)
        var project = makeProject()
        project.assets[0].url = directory.appendingPathComponent("old-location.gpx")
        project.assets[0].relativePath = media.lastPathComponent
        let date = Date(timeIntervalSince1970: 1_783_641_600)
        project.assets[0].weatherRecords = [TimelineWeatherRecord(timestamp: date, temperatureCelsius: 32, humidityPercent: 71, summary: "Clear")]
        project.tracks[0].clips[0].layout = OverlayLayout(elements: [
            OverlayElement(id: "weather", kind: .weather, frame: OverlayComponentFrame(x: 0.1, y: 0.1, scale: 2)),
            OverlayElement(id: "distance", kind: .distance, frame: OverlayComponentFrame(x: 0.1, y: 0.65, scale: 2))
        ])
        let projectURL = directory.appendingPathComponent("project.dlsproj")
        let output = directory.appendingPathComponent("cli.mov")
        let reference = directory.appendingPathComponent("gui-writer.mov")
        try JSONEncoder().encode(project).write(to: projectURL)
        try renderTimelineProject(options: options(["--output", output.path]), projectURL: projectURL)

        let raw = try TelemetryFileParser().parseActivity(url: media).series
        let expectedSeries = TelemetrySeries(samples: raw.samples.map { sample in
            var enriched = sample
            enriched.weatherTemperatureCelsius = 32
            enriched.weatherHumidityPercent = 71
            enriched.weatherSummary = "Clear"
            return enriched
        })
        project.assets[0].url = media
        try TimelineVideoWriter(
            outputURL: reference, project: project, telemetrySeriesByAssetID: ["activity": expectedSeries],
            config: TimelineVideoWriterConfig(width: 320, height: 180, framesPerSecond: 4, timelineStart: 1, duration: 2,
                averageBitRate: 650_000, codec: .h264, activityTrim: ActivityTrim(startSeconds: 1, endSeconds: 3))
        ).write()
        let movie = AVURLAsset(url: output)
        let duration = try await movie.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), 2, accuracy: 0.01)
        let tracks = try await movie.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let (size, fps, formats) = try await track.load(.naturalSize, .nominalFrameRate, .formatDescriptions)
        XCTAssertEqual(size, CGSize(width: 320, height: 180))
        XCTAssertEqual(fps, 4)
        let format = try XCTUnwrap(formats.first)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_H264)
        let actual = try await decodedFrames(output)
        let expected = try await decodedFrames(reference)
        XCTAssertEqual(actual.count, 8)
        XCTAssertEqual(actual.count, expected.count)
        for (frame, referenceFrame) in zip(actual, expected) {
            XCTAssertEqual(frame.count, referenceFrame.count)
            let difference = zip(frame, referenceFrame).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
            XCTAssertLessThan(difference / Double(frame.count), 1)
        }
    }

    func testIndividualAlphaClipsInheritSavedScopeCodecAndRange() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let media = directory.appendingPathComponent("activity.gpx")
        try Data(gpx.utf8).write(to: media)
        var project = makeProject()
        project.assets[0].url = media
        project.exportSettings?.exportMode = .overlay
        project.exportSettings?.codec = .proRes4444
        project.exportSettings?.renderScope = .individualClips
        let layout = OverlayLayout(elements: [OverlayElement(id: "distance", kind: .distance,
            frame: OverlayComponentFrame(x: 0.2, y: 0.2, scale: 2))])
        project.tracks[0].clips = [
            TimelineClip(id: "one", assetID: "activity", timelineStart: 0, duration: 2, layout: layout),
            TimelineClip(id: "two", assetID: "activity", timelineStart: 2, duration: 2, sourceIn: 2, layout: layout)
        ]
        let projectURL = directory.appendingPathComponent("project.dlsproj")
        let output = directory.appendingPathComponent("output.mov")
        try JSONEncoder().encode(project).write(to: projectURL)
        try renderTimelineProject(options: options(["--output", output.path]), projectURL: projectURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        for name in ["output_01.mov", "output_02.mov"] {
            let url = directory.appendingPathComponent(name)
            let movie = AVURLAsset(url: url)
            let duration = try await movie.load(.duration)
            XCTAssertEqual(CMTimeGetSeconds(duration), 1, accuracy: 0.01)
            let tracks = try await movie.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let formats = try await track.load(.formatDescriptions)
            let format = try XCTUnwrap(formats.first)
            XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_AppleProRes4444)
            let frames = try await decodedFrames(url)
            XCTAssertEqual(frames.count, 4)
            let frame = try XCTUnwrap(frames.first)
            XCTAssertEqual(frame[3], 0)
            XCTAssertTrue(stride(from: 3, to: frame.count, by: 4).contains { frame[$0] > 0 })
        }
    }

    private func options(_ extra: [String] = []) throws -> CommandLineOptions {
        try CommandLineOptions.parse(arguments: ["overlay", "--timeline-project", "project.dlsproj", "--output", "output.mov"] + extra)
    }

    private func makeProject() -> TimelineProject {
        TimelineProject(outputWidth: 320, outputHeight: 180, framesPerSecond: 4, distanceUnit: .kilometers,
            assets: [MediaAsset(id: "activity", kind: .activity, url: URL(fileURLWithPath: "/missing/activity.gpx"), displayName: "Activity", duration: 4)],
            tracks: [TimelineTrack(id: "overlay", kind: .overlay, name: "Data", clips: [
                TimelineClip(id: "data", assetID: "activity", timelineStart: 0, duration: 4)
            ])], exportSettings: TimelineProjectExportSettings(timelineStart: 1, timelineEnd: 3,
                activityTrim: ActivityTrim(startSeconds: 1, endSeconds: 3), exportMode: .video, codec: .h264, bitRateKbps: 650))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CLIProjectTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func decodedFrames(_ url: URL) async throws -> [Data] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frames: [Data] = []
        while let sample = output.copyNextSampleBuffer() {
            let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
            var frame = Data()
            for row in 0..<CVPixelBufferGetHeight(buffer) {
                frame.append(base.advanced(by: row * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self), count: CVPixelBufferGetWidth(buffer) * 4)
            }
            frames.append(frame)
        }
        XCTAssertEqual(reader.status, .completed)
        return frames
    }

    private var gpx: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="DataLayer Studio" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
        <trkpt lat="35.0" lon="139.0"><time>2026-07-10T00:00:00Z</time></trkpt>
        <trkpt lat="35.0001" lon="139.0001"><time>2026-07-10T00:00:04Z</time></trkpt>
        </trkseg></trk></gpx>
        """
    }
}
