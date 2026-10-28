#if os(Linux) || os(Windows)
import Foundation
import XCTest
@testable import OverlayCore

final class PortableMediaTests: XCTestCase {
    func testAudioPaddingWithMissingTimestampsHasAnExactFiniteSampleCount() throws {
        for (timestamp, duration) in [("NAN", 0.1), ("if(gte(N,1024),NAN,PTS)", 0.10001)] {
            let process = Process(), output = Pipe()
            process.executableURL = try PortableMedia.executable("ffmpeg")
            let graph = "[0:a]aformat=sample_fmts=fltp:channel_layouts=stereo,asetpts='\(timestamp)'[input];" +
                PortableVideoExport.audioMixFilter(labels: ["input"], duration: duration)
            process.arguments = ["-v", "error", "-nostdin", "-f", "lavfi", "-i", "sine=sample_rate=48000:duration=0.04",
                                 "-filter_complex", graph, "-map", "[audio]", "-f", "s16le", "-fs", "65536", "pipe:1"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = try XCTUnwrap(output.fileHandleForReading.readToEnd())
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertEqual(data.count, Int((duration * 48_000).rounded(.up)) * 4)
            XCTAssertTrue(data.prefix(1920 * 4).contains { $0 != 0 }, "Preserve the audible source")
            XCTAssertTrue(data.dropFirst(1920 * 4).allSatisfy { $0 == 0 }, "Pad only the remaining samples with silence")
        }
    }

    func testHEVCAlphaIsRejectedWithoutTouchingExistingOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("keep.mov"), sentinel = Data("original".utf8)
        try sentinel.write(to: output)
        XCTAssertThrowsError(try TransparentVideoWriter(outputURL: output, series: series(), config: configuration(codec: .hevcAlpha)).write()) { error in
            guard case let OverlayVideoError.unsupportedEncoder(message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("HEVC Alpha")); XCTAssertTrue(message.contains("ProRes 4444"))
        }
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["keep.mov"])
    }

    func testProResHasRealAlphaAndExactFractionalFrameTiming() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("alpha.mov")
        let config = configuration(codec: .proRes4444)
        try TransparentVideoWriter(outputURL: output, series: series(), config: config).write()
        let probe = try PortableMedia.probe(output), stream = try XCTUnwrap(probe.video)
        XCTAssertEqual(stream.codec_name, "prores")
        XCTAssertEqual(stream.nb_frames, "41")
        XCTAssertEqual(stream.avg_frame_rate, "30000/1001")
        XCTAssertEqual(try XCTUnwrap(Double(stream.duration ?? "")), 41 * 1001.0 / 30_000, accuracy: 0.000001)
        let frame = try firstFrame(output)
        XCTAssertEqual(frame.count, 320 * 180 * 4)
        for pixel in [0, 319, 320 * 179, 320 * 180 - 1] { XCTAssertEqual(frame[pixel * 4 + 3], 0) }
        let alpha = stride(from: 3, to: frame.count, by: 4).map { frame[$0] }
        XCTAssertTrue(alpha.contains(0)); XCTAssertTrue(alpha.contains { $0 > 0 && $0 < 255 })
        XCTAssertTrue(alpha.contains { $0 > 200 })
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".DataLayerStudio-") })
    }

    func testCancellationAfterWritingStartsPreservesDestinationAndCleansScratch() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("keep.mov"), sentinel = Data("original".utf8)
        try sentinel.write(to: output)
        let cancellation = CancellationFlag()
        var config = configuration(codec: .proRes4444)
        config.cancellationHandler = { cancellation.value }
        config.progressHandler = { frame, _ in if frame == 1 { cancellation.set() } }
        XCTAssertThrowsError(try TransparentVideoWriter(outputURL: output, series: series(), config: config).write()) { error in
            guard case OverlayVideoError.cancelled = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["keep.mov"])
    }

    func testMissingMediaCannotReplaceDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("keep.mov"), sentinel = Data("original".utf8)
        try sentinel.write(to: output)
        let asset = MediaAsset(id: "missing", kind: .video, url: directory.appendingPathComponent("missing.mov"), displayName: "missing", duration: 2)
        let project = TimelineProject(outputWidth: 320, outputHeight: 180, framesPerSecond: 30, distanceUnit: .kilometers, assets: [asset], tracks: [
            TimelineTrack(id: "video", kind: .video, name: "video", clips: [TimelineClip(id: "clip", assetID: asset.id, timelineStart: 0, duration: 2)])
        ])
        XCTAssertThrowsError(try TimelineVideoWriter(outputURL: output, project: project, telemetrySeriesByAssetID: [:], config: .init(width: 320, height: 180, framesPerSecond: 30, duration: 2, codec: .h264)).write())
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["keep.mov"])
    }

    func testCrashCleanupDeletesOnlyRecognizedDeadExporterDirectories() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        func scratch(pid: Int32, extra: String? = nil) throws -> URL {
            let directory = root.appendingPathComponent(".DataLayerStudio-Export-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let owner: [String: Any] = ["application": "DataLayer-CLI", "version": 1, "pid": pid, "createdAt": Date().addingTimeInterval(-120).timeIntervalSinceReferenceDate]
            try JSONSerialization.data(withJSONObject: owner).write(to: directory.appendingPathComponent("owner.json"))
            try Data("partial".utf8).write(to: directory.appendingPathComponent(extra ?? "output.mov"))
            return directory
        }
        let dead = try scratch(pid: Int32.max), active = try scratch(pid: ProcessInfo.processInfo.processIdentifier)
        let unknown = try scratch(pid: Int32.max, extra: "user-data.txt")
        TransparentVideoWriter.removeStaleTemporaryOutputs(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dead.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
    }

    func testNTSCExportRangeRoundsOnlyAtTheFinalFrameBoundary() {
        let timing = TransparentVideoFrameTiming(framesPerSecond: 29.97, duration: 4.5)
        XCTAssertEqual(timing.frameCount, 135)
        XCTAssertEqual(timing.presentationTime(for: 134).value, 134 * 1001)
        XCTAssertEqual(timing.outputDuration.timescale, 30_000)
        XCTAssertEqual(timing.outputDuration.seconds, 4.5045, accuracy: 0.000000001)
    }

    func testOpaqueVideoCompositesAlphaInLinearLight() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("linear.mov")
        try PortableVideoExport.write(outputURL: output, project: nil, config: .init(width: 16, height: 16, framesPerSecond: 30, duration: 0.1, codec: .h264)) { _, buffer in
            buffer.pixels.initializeMemory(as: UInt8.self, repeating: 128, count: buffer.bytesPerRow * buffer.height)
        }
        let pixel = try firstFrame(output)[0]
        XCTAssertGreaterThan(pixel, 175, "A gamma-space blend would incorrectly produce 128")
        XCTAssertLessThan(pixel, 185, "The native Rec.709 ICC curve must be preserved")
    }

    func testDrawingTextPreservesTheCurrentGraphicsPath() throws {
        let buffer = CVPixelBuffer(width: 64, height: 64)
        do {
            let context = try XCTUnwrap(CGContext(data: buffer.pixels, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: buffer.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: 0))
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.setLineWidth(2)
            context.move(to: CGPoint(x: 2, y: 2))
            context.addLine(to: CGPoint(x: 8, y: 2))
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "X", attributes: [
                NSAttributedString.Key(kCTFontAttributeName): CTFontCreateWithName("Menlo-Bold", 8, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName): CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            ]))
            context.textPosition = CGPoint(x: 52, y: 52)
            CTLineDraw(line, context)
            context.addLine(to: CGPoint(x: 8, y: 8))
            context.strokePath()
        }
        let middleAlpha = (20..<44).flatMap { y in (20..<44).map { x in
            buffer.pixels.load(fromByteOffset: (y * 64 + x) * 4 + 3, as: UInt8.self)
        } }
        XCTAssertTrue(middleAlpha.allSatisfy { $0 == 0 },
            "Text must not connect its baseline to the following gauge or route path")
        XCTAssertGreaterThan(buffer.pixels.load(fromByteOffset: (61 * 64 + 4) * 4 + 3, as: UInt8.self), 0,
            "The path that preceded the text must remain intact")
    }

    func testDisabledAntialiasingKeepsHardEdgesAndRestoresState() throws {
        let buffer = CVPixelBuffer(width: 64, height: 32)
        do {
            let context = try XCTUnwrap(CGContext(data: buffer.pixels, width: 64, height: 32, bitsPerComponent: 8,
                bytesPerRow: buffer.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: 0))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.saveGState()
            context.setShouldAntialias(false)
            context.fill(CGRect(x: 8.25, y: 8.25, width: 8.5, height: 8.5))
            context.restoreGState()
            context.fill(CGRect(x: 40.25, y: 8.25, width: 8.5, height: 8.5))
        }
        var hard: [UInt8] = [], smooth: [UInt8] = []
        for y in 0..<32 { for x in 0..<32 {
            hard.append(buffer.pixels.load(fromByteOffset: (y * 64 + x) * 4 + 3, as: UInt8.self))
            smooth.append(buffer.pixels.load(fromByteOffset: (y * 64 + x + 32) * 4 + 3, as: UInt8.self))
        } }
        XCTAssertTrue(hard.contains(255))
        XCTAssertFalse(hard.contains { $0 > 0 && $0 < 255 })
        XCTAssertTrue(smooth.contains { $0 > 0 && $0 < 255 })
    }

    func testShadowOpacityIncludesThePaintsAlpha() throws {
        let buffer = CVPixelBuffer(width: 64, height: 64)
        do {
            let context = try XCTUnwrap(CGContext(data: buffer.pixels, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: buffer.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: 0))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
            context.setShadow(offset: .zero, blur: 0, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
            context.fill(CGRect(x: 16, y: 16, width: 32, height: 32))
        }
        let alpha = buffer.pixels.load(fromByteOffset: (32 * 64 + 32) * 4 + 3, as: UInt8.self)
        // Source-over: 0.5 + (0.5 * 0.5) * (1 - 0.5) = 0.625, rather than 0.75.
        XCTAssertEqual(Double(alpha), 0.625 * 255, accuracy: 2)
    }

    func testFractionalTrimAndCutSelectSourceFramesWithinApplesHalfFrameTolerance() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("alternating.mkv"), output = directory.appendingPathComponent("trimmed.mov")
        let process = Process()
        process.executableURL = try PortableMedia.executable("ffmpeg")
        process.arguments = ["-v", "error", "-f", "lavfi", "-i", "nullsrc=s=64x64:r=30000/1001:d=2,geq=lum='64+120*mod(N,2)':cb=128:cr=128", "-c:v", "ffv1", source.path]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let asset = MediaAsset(id: "video", kind: .video, url: source, displayName: "alternating", duration: 2)
        let project = TimelineProject(outputWidth: 64, outputHeight: 64, framesPerSecond: 29.97, distanceUnit: .kilometers, assets: [asset], tracks: [
            TimelineTrack(id: "video", kind: .video, name: "video", clips: [
                TimelineClip(id: "clip", assetID: asset.id, timelineStart: 0, duration: 1.4, sourceIn: 0.2),
                TimelineClip(id: "next", assetID: asset.id, timelineStart: 1.4, duration: 0.3, sourceIn: 0.3667)
            ])
        ])
        try TimelineVideoWriter(outputURL: output, project: project, telemetrySeriesByAssetID: [:], config: .init(width: 64, height: 64, framesPerSecond: 29.97, timelineStart: 1.35, duration: 0.1, codec: .h264)).write()
        // At source 1.55 s the native reader holds dark frame 46; rounding the filter clock selects bright frame 47.
        let frames = try firstFrame(output, count: 2)
        XCTAssertGreaterThan(frames[0], 40); XCTAssertLessThan(frames[0], 80)
        XCTAssertGreaterThan(frames[64 * 64 * 4], 160, "The next clip must not appear one frame before its start")
    }

    private func configuration(codec: OverlayVideoCodec) -> TransparentVideoWriterConfig {
        var weather = OverlayElement.defaultElement(kind: .weather)
        weather.frame = OverlayComponentFrame(x: 0.5, y: 0.5, scale: 0.6)
        return .init(width: 320, height: 180, framesPerSecond: 29.97, duration: 1.35, codec: codec, overlayLayout: .init(elements: [weather]))
    }
    private func series() -> TelemetrySeries {
        var sample = TelemetrySample(elapsed: 0, date: Date(timeIntervalSince1970: 1_700_000_000))
        sample.weatherTemperatureCelsius = 31; sample.weatherHumidityPercent = 57; sample.weatherSummary = "Clear"
        var last = sample; last.elapsed = 2
        return TelemetrySeries(samples: [sample, last])
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DataLayerPortableTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func firstFrame(_ url: URL, count: Int = 1) throws -> Data {
        let process = Process(), output = Pipe()
        process.executableURL = try PortableMedia.executable("ffmpeg")
        process.arguments = ["-v", "error", "-i", url.path, "-frames:v", "\(count)", "-f", "rawvideo", "-pix_fmt", "bgra", "pipe:1"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = try XCTUnwrap(output.fileHandleForReading.readToEnd()); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0); return data
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func set() { lock.lock(); flag = true; lock.unlock() }
}
#endif
