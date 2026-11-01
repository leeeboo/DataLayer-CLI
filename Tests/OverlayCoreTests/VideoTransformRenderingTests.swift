#if canImport(AVFoundation)
import AVFoundation
import CoreVideo
@testable import OverlayCore
import XCTest

final class VideoTransformRenderingTests: XCTestCase {
    private let palette: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]

    func testEveryRotationAndFlipMatchesEncodedVideoAndKeepsOverlayUpright() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("corners.mov")
        let output = directory.appendingPathComponent("output.mov")
        try await makeSource(at: source)
        let transforms = (0..<4).flatMap { turns in
            [false, true].flatMap { horizontal in
                [false, true].map { VideoTransform(quarterTurns: turns, flipHorizontal: horizontal, flipVertical: $0) }
            }
        } + [VideoTransform(quarterTurns: 4), VideoTransform(quarterTurns: 5, flipHorizontal: true)]
        let duration = Double(transforms.count)
        let overlay = OverlayLayout(elements: [OverlayElement(id: "heart", kind: .heartRate,
            frame: OverlayComponentFrame(x: 0.02, y: 0.02),
            customization: OverlayElementCustomization(showsLabel: false, showsUnit: false, showsPanel: false,
                valueColor: OverlayColor(red: 1, green: 1, blue: 1)))])
        let project = TimelineProject(outputWidth: 320, outputHeight: 320, framesPerSecond: 2, distanceUnit: .kilometers,
            assets: [MediaAsset(id: "video", kind: .video, url: source, displayName: "corners", duration: 1),
                     MediaAsset(id: "activity", kind: .activity, url: directory.appendingPathComponent("activity.fit"), displayName: "Activity", duration: duration)],
            tracks: [TimelineTrack(id: "video", kind: .video, name: "V", clips: transforms.enumerated().map { index, transform in
                TimelineClip(id: "v\(index)", assetID: "video", timelineStart: Double(index), duration: 1, videoTransform: transform)
            }), TimelineTrack(id: "overlay", kind: .overlay, name: "O", clips: [
                TimelineClip(id: "o", assetID: "activity", timelineStart: 0, duration: duration, layout: overlay)
            ])])
        let clips = try project.validatedVideoClipsForExport(timelineStart: 0, duration: duration)
        let preview = try TimelineVideoCompositionBuilder.make(project: project, videoClips: clips, requiredEnd: duration)
        let previewFrames = try inspectFrames(asset: preview.composition, videoComposition: preview.videoComposition, transforms: transforms)
        XCTAssertEqual(previewFrames.count, transforms.count * 2)

        _ = try TimelineVideoWriter(outputURL: output, project: project,
            telemetrySeriesByAssetID: ["activity": TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, heartRate: 150), TelemetrySample(elapsed: duration, heartRate: 150)
            ])],
            config: TimelineVideoWriterConfig(width: 320, height: 320, framesPerSecond: 2,
                timelineStart: 0, duration: duration, averageBitRate: 2_000_000, codec: .h264)).write()
        let encodedFrames = try inspectFrames(asset: AVURLAsset(url: output), transforms: transforms)
        XCTAssertEqual(encodedFrames.count, previewFrames.count)
        let baseline = try XCTUnwrap(encodedFrames.first)
        XCTAssertGreaterThan(baseline.count, 5, "The telemetry component must actually be visible")
        for frame in encodedFrames {
            XCTAssertEqual(frame.minX, baseline.minX, accuracy: 2)
            XCTAssertEqual(frame.minY, baseline.minY, accuracy: 2)
            XCTAssertEqual(frame.maxX, baseline.maxX, accuracy: 2)
            XCTAssertEqual(frame.maxY, baseline.maxY, accuracy: 2)
        }
    }

    private struct WhiteBounds {
        var minX = 320.0, minY = 320.0, maxX = 0.0, maxY = 0.0
        var count = 0
    }

    private func inspectFrames(asset: AVAsset, videoComposition: AVVideoComposition? = nil,
                               transforms: [VideoTransform]) throws -> [WhiteBounds] {
        let reader = try AVAssetReader(asset: asset)
        let settings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let output: AVAssetReaderOutput
        if let videoComposition {
            let composed = AVAssetReaderVideoCompositionOutput(videoTracks: asset.tracks(withMediaType: .video), videoSettings: settings)
            composed.videoComposition = videoComposition
            output = composed
        } else {
            output = AVAssetReaderTrackOutput(track: try XCTUnwrap(asset.tracks(withMediaType: .video).first), outputSettings: settings)
        }
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var result: [WhiteBounds] = []
        while let sample = output.copyNextSampleBuffer() {
            let frame = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let index = min(transforms.count - 1, Int(time))
            let transform = transforms[index]
            // JianYing mirrors the source axes before rotation, regardless of action order.
            var corners = [0, 1, 2, 3]
            if transform.flipHorizontal { corners = [corners[1], corners[0], corners[3], corners[2]] }
            if transform.flipVertical { corners = [corners[2], corners[3], corners[0], corners[1]] }
            let order = [[0, 1, 2, 3], [2, 0, 3, 1], [3, 2, 1, 0], [1, 3, 0, 2]][transform.normalizedQuarterTurns]
            corners = order.map { corners[$0] }
            let portrait = !transform.quarterTurns.isMultiple(of: 2)
            let points = portrait ? [(112, 80), (208, 80), (112, 240), (208, 240)]
                                  : [(80, 112), (240, 112), (80, 208), (240, 208)]
            CVPixelBufferLockBaseAddress(frame, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(frame)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(frame)
            for (corner, point) in points.enumerated() {
                let offset = point.1 * stride + point.0 * 4
                for channel in 0..<3 {
                    XCTAssertEqual(Double(bytes[offset + 2 - channel]), Double(palette[corners[corner]][channel]), accuracy: 40,
                        "t=\(time), \(transform), corner \(corner), channel \(channel)")
                }
            }
            var white = WhiteBounds()
            for y in 0..<320 {
                for x in 0..<320 {
                    let offset = y * stride + x * 4
                    if bytes[offset] > 235 && bytes[offset + 1] > 235 && bytes[offset + 2] > 235 {
                        white.minX = min(white.minX, Double(x)); white.maxX = max(white.maxX, Double(x))
                        white.minY = min(white.minY, Double(y)); white.maxY = max(white.maxY, Double(y))
                        white.count += 1
                    }
                }
            }
            result.append(white)
        }
        XCTAssertEqual(reader.status, .completed, "\(String(describing: reader.error))")
        return result
    }

    func testQuarterTurnRetainsScaleAndCropsLandscapeCanvasInPreviewAndExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mov"), output = directory.appendingPathComponent("output.mov")
        try await makeSource(at: source)
        let project = TimelineProject(outputWidth: 320, outputHeight: 192, framesPerSecond: 2, distanceUnit: .kilometers,
            assets: [MediaAsset(id: "v", kind: .video, url: source, displayName: "Source", duration: 1)],
            tracks: [TimelineTrack(id: "v", kind: .video, name: "V", clips: [
                TimelineClip(id: "c", assetID: "v", timelineStart: 0, duration: 1, videoTransform: VideoTransform(quarterTurns: 1))])])
        let built = try TimelineVideoCompositionBuilder.make(project: project, videoClips: project.enabledClips(kind: .video), requiredEnd: 1)
        _ = try TimelineVideoWriter(outputURL: output, project: project, telemetrySeriesByAssetID: [:],
            config: TimelineVideoWriterConfig(width: 320, height: 192, framesPerSecond: 2,
                timelineStart: 0, duration: 1, codec: .h264)).write()
        for (asset, composition) in [(built.composition as AVAsset, built.videoComposition as AVVideoComposition?),
                                      (AVURLAsset(url: output) as AVAsset, nil)] {
            let reader = try AVAssetReader(asset: asset)
            let settings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
            let sampleOutput: AVAssetReaderOutput
            if let composition {
                let composed = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: settings)
                composed.videoComposition = composition
                sampleOutput = composed
            } else { sampleOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings) }
            reader.add(sampleOutput)
            XCTAssertTrue(reader.startReading())
            let sample = try XCTUnwrap(sampleOutput.copyNextSampleBuffer())
            let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            XCTAssertGreaterThan(bytes[48 * stride + 80 * 4], 210, "Clockwise blue corner keeps original scale; auto-fit would leave this point black")
            XCTAssertLessThan(bytes[96 * stride + 16 * 4], 20, "The side letterbox remains black")
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            reader.cancelReading()
        }
    }

    private func makeSource(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 80, AVVideoHeightKey: 48
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 80, kCVPixelBufferHeightKey as String: 48,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frameIndex in 0..<2 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
            XCTAssertTrue(input.isReadyForMoreMediaData)
            var pixel: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &pixel), kCVReturnSuccess)
            let buffer = try XCTUnwrap(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<48 {
                for x in 0..<80 {
                    let rgb = palette[(y < 24 ? 0 : 2) + (x < 40 ? 0 : 1)]
                    let offset = y * stride + x * 4
                    bytes[offset] = rgb[2]; bytes[offset + 1] = rgb[1]; bytes[offset + 2] = rgb[0]; bytes[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frameIndex), timescale: 2)))
        }
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
    }
}
#endif
