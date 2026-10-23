import AVFoundation
import CoreVideo
import Foundation
@testable import OverlayCore
import XCTest

final class OverlayTimeZoneTests: XCTestCase {
    func testFITTimeZoneMetadataDoesNotChangeTelemetryOrUTC() throws {
        let baseline = try FITParser().parseActivity(data: fitFile())
        for offset in [0, 28_800, -18_000, 19_800, 20_700, -43_200, 50_400] {
            let activity = try FITParser().parseActivity(data: fitFile(offset: offset))
            XCTAssertEqual(activity.timeZoneOffsetSeconds, offset)
            XCTAssertEqual(activity.series, baseline.series)
            XCTAssertEqual(activity.series.activityStartDate, Date(timeIntervalSince1970: 1_631_065_600))
        }
        XCTAssertNil(baseline.timeZoneOffsetSeconds)
    }

    func testFITActivityOffsetTakesPriorityAndInvalidValuesFallBack() throws {
        let parser = FITParser()
        XCTAssertEqual(try parser.parseActivity(data: fitFile(offset: 0, deviceOffsets: [36])).timeZoneOffsetSeconds, 0)
        XCTAssertEqual(try parser.parseActivity(data: fitFile(deviceOffsets: [32, -20], activeIndex: 1)).timeZoneOffsetSeconds, -18_000)
        XCTAssertEqual(try parser.parseActivity(data: fitFile(offset: 100_000, deviceOffsets: [22])).timeZoneOffsetSeconds, 19_800)
        XCTAssertEqual(try parser.parseActivity(data: fitFile(deviceOffsets: [23], activeIndex: nil)).timeZoneOffsetSeconds, 20_700)
        for data in [fitFile(offset: -100_000), fitFile(deviceOffsets: [127]),
                     fitFile(deviceOffsets: [32, 36], activeIndex: nil),
                     fitFile(deviceOffsets: [32], activeIndex: 2),
                     fitFile(offset: Int(UInt32.max) - 1_000_000_010)] {
            XCTAssertNil(try parser.parseActivity(data: data).timeZoneOffsetSeconds)
        }
    }

    func testGPXPreservesExplicitOffsetWithoutShiftingDates() throws {
        let beijing = try GPXParser().parseActivity(data: gpx("2026-10-18T07:30:00+08:00"))
        let tokyo = try GPXParser().parseActivity(data: gpx("2026-10-18T08:30:00+09:00"))
        let utc = try GPXParser().parseActivity(data: gpx("2026-10-17T23:30:00Z"))
        XCTAssertEqual(beijing.timeZoneOffsetSeconds, 28_800)
        XCTAssertEqual(tokyo.timeZoneOffsetSeconds, 32_400)
        XCTAssertEqual(utc.timeZoneOffsetSeconds, 0)
        XCTAssertEqual(beijing.series, tokyo.series)
        XCTAssertEqual(beijing.series, utc.series)
        XCTAssertEqual(try GPXParser().parseActivity(data: gpx("2026-10-18T05:15:00+05:45")).timeZoneOffsetSeconds, 20_700)
        XCTAssertEqual(try GPXParser().parseActivity(data: gpx("2026-10-17T18:30:00-0500")).timeZoneOffsetSeconds, -18_000)
        XCTAssertNil(try GPXParser().parseActivity(data: gpx(nil)).timeZoneOffsetSeconds)
    }

    func testAutomaticFallbackAndManualChoice() throws {
        let system = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        XCTAssertEqual(OverlayTimeZone.activity.resolve(activityOffsetSeconds: 0, systemTimeZone: system).secondsFromGMT(), 0)
        XCTAssertEqual(OverlayTimeZone.activity.resolve(activityOffsetSeconds: 28_800, systemTimeZone: system).secondsFromGMT(), 28_800)
        XCTAssertEqual(OverlayTimeZone.activity.resolve(activityOffsetSeconds: nil, systemTimeZone: system), system)
        XCTAssertEqual(OverlayTimeZone.activity.resolve(activityOffsetSeconds: .max, systemTimeZone: system), system)
        XCTAssertEqual(OverlayTimeZone.system.resolve(activityOffsetSeconds: 28_800, systemTimeZone: system), system)
        XCTAssertEqual(OverlayTimeZone(rawValue: "Asia/Shanghai")?.resolve(activityOffsetSeconds: -18_000).identifier, "Asia/Shanghai")
        XCTAssertNil(OverlayTimeZone(rawValue: "Invalid/TimeZone"))
        XCTAssertThrowsError(try JSONDecoder().decode(OverlayTimeZone.self, from: Data("\"Invalid/TimeZone\"".utf8)))
    }

    func testClockDateAndDSTUseSelectedZoneWithoutChangingSync() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-17T23:30:00Z"))
        let series = TelemetrySeries(samples: [TelemetrySample(elapsed: 0, date: date, distanceMeters: 0),
                                               TelemetrySample(elapsed: 120, date: date.addingTimeInterval(120), distanceMeters: 360)])
        func renderer(_ zone: TimeZone) -> OverlayRenderer {
            OverlayRenderer(series: series, config: .init(size: CGSize(width: 640, height: 360),
                timeSync: .init(videoSyncTime: 3, fitSyncTime: 4), timeZone: zone))
        }
        let utc = renderer(TimeZone(secondsFromGMT: 0)!)
        let beijing = renderer(TimeZone(secondsFromGMT: 28_800)!)
        XCTAssertEqual(beijing.formatClockAndCalendarDate(date).clock, "07:30:00")
        XCTAssertEqual(beijing.formatClockAndCalendarDate(date).date, "2026/10/18")
        XCTAssertEqual(utc.formatClockAndCalendarDate(date).date, "2026/10/17")
        XCTAssertEqual(utc.resolvedFrame(atVideoTime: 30), beijing.resolvedFrame(atVideoTime: 30))
        let la = renderer(TimeZone(identifier: "America/Los_Angeles")!)
        let before = ISO8601DateFormatter().date(from: "2026-03-08T09:30:00Z")!
        XCTAssertEqual(la.formatClockAndCalendarDate(before).clock, "01:30:00")
        XCTAssertEqual(la.formatClockAndCalendarDate(before.addingTimeInterval(3600)).clock, "03:30:00")
        XCTAssertFalse(OverlayRenderConfig(size: .zero, timeZone: TimeZone(secondsFromGMT: 0)!)
            .matchesIgnoringLayout(OverlayRenderConfig(size: .zero, timeZone: TimeZone(secondsFromGMT: 28_800)!)))
    }

    func testProjectAndWorkerRoundTripKeepSelectionAndFileMetadata() throws {
        var project = TimelineProject(outputWidth: 640, outputHeight: 360, framesPerSecond: 30,
                                      distanceUnit: .kilometers, assets: [
            MediaAsset(id: "fit", kind: .activity, url: URL(fileURLWithPath: "/tmp/test.fit"),
                       displayName: "test", duration: 10, timeZoneOffsetSeconds: 28_800)
        ])
        for selection in [OverlayTimeZone.activity, .system, OverlayTimeZone(rawValue: "Asia/Tokyo")!] {
            project.timeZone = selection
            let reopened = try JSONDecoder().decode(TimelineProject.self, from: JSONEncoder().encode(project))
            XCTAssertEqual(reopened, project)
        }
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        legacy.removeValue(forKey: "timeZone")
        let reopened = try JSONDecoder().decode(TimelineProject.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(reopened.timeZone, .activity)
        XCTAssertEqual(reopened.displayTimeZone().secondsFromGMT(), 28_800)
        var other = project.assets[0]
        other.id = "other"; other.timeZoneOffsetSeconds = -18_000
        XCTAssertEqual(reopened.displayTimeZone(for: other).secondsFromGMT(), -18_000)
        let config = TransparentVideoWriterConfig(width: 640, height: 360, framesPerSecond: 30,
                                                  duration: 1, timeZone: reopened.displayTimeZone())
        let workerConfig = try PropertyListDecoder().decode(TransparentVideoWriterConfig.self,
                                                            from: PropertyListEncoder().encode(config))
        XCTAssertEqual(workerConfig.timeZone, config.timeZone)
    }

    func testPreviewTimeZoneChangeInvalidatesCachedPixels() throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-17T23:30:00Z")!
        let series = TelemetrySeries(samples: [TelemetrySample(elapsed: 0, date: date)])
        let preview = OverlayPreviewRenderer()
        let layout = OverlayLayout(elements: [OverlayElement.defaultElement(kind: .timeDate)])
        func pixels(_ zone: TimeZone) throws -> Data {
            let image = try preview.renderOverlayImage(series: series, size: CGSize(width: 640, height: 360),
                videoTime: 0, layout: layout, timeZone: zone)
            return try XCTUnwrap(image.dataProvider?.data) as Data
        }
        let beijing = try pixels(TimeZone(secondsFromGMT: 28_800)!)
        XCTAssertNotEqual(beijing, try pixels(TimeZone(secondsFromGMT: 0)!))
        XCTAssertEqual(beijing, try pixels(TimeZone(secondsFromGMT: 28_800)!))
    }

    func testEncodedClockUsesFileAndManualZonesAcrossExportPaths() async throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-17T23:30:00Z")!
        let series = TelemetrySeries(samples: [TelemetrySample(elapsed: 0, date: date),
            TelemetrySample(elapsed: 1, date: date.addingTimeInterval(1))])
        let layout = OverlayLayout(elements: [OverlayElement.defaultElement(kind: .timeDate)])
        for (codec, clipCount) in [(OverlayVideoCodec.proRes4444, 1), (.proRes4444, 2), (.h264, 1)] {
            var project = TimelineProject(outputWidth: 640, outputHeight: 360, framesPerSecond: 2,
                distanceUnit: .kilometers, assets: [MediaAsset(id: "activity", kind: .activity,
                    url: URL(fileURLWithPath: "/tmp/clock.fit"), displayName: "clock", duration: 1,
                    timeZoneOffsetSeconds: 28_800)], tracks: [TimelineTrack(id: "overlay", kind: .overlay,
                        name: "A1", clips: (0..<clipCount).map { index in
                            TimelineClip(id: "clip\(index)", assetID: "activity",
                                timelineStart: Double(index) / Double(clipCount),
                                duration: 1 / Double(clipCount), layout: layout)
                        })])
            var frames: [Data] = []
            for zone in [OverlayTimeZone.activity, OverlayTimeZone(rawValue: "Asia/Shanghai")!,
                         OverlayTimeZone(rawValue: "UTC")!] {
                project.timeZone = zone
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("clock-\(UUID()).mov")
                defer { try? FileManager.default.removeItem(at: url) }
                try TimelineVideoWriter(outputURL: url, project: project,
                    telemetrySeriesByAssetID: ["activity": series], config: .init(width: 640, height: 360,
                        framesPerSecond: 2, duration: 1, codec: codec)).write()
                let asset = AVURLAsset(url: url)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                let track = try XCTUnwrap(tracks.first)
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track,
                    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                reader.add(output)
                XCTAssertTrue(reader.startReading())
                var pixels = Data()
                while let sample = output.copyNextSampleBuffer() {
                    let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
                    CVPixelBufferLockBaseAddress(buffer, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                    let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
                    for row in 0..<CVPixelBufferGetHeight(buffer) {
                        pixels.append(base.advanced(by: row * CVPixelBufferGetBytesPerRow(buffer))
                            .assumingMemoryBound(to: UInt8.self), count: CVPixelBufferGetWidth(buffer) * 4)
                    }
                }
                XCTAssertEqual(reader.status, .completed)
                XCTAssertFalse(pixels.isEmpty)
                frames.append(pixels)
            }
            XCTAssertEqual(frames[0], frames[1], "File offset must match Asia/Shanghai: \(codec), \(clipCount) clips")
            XCTAssertNotEqual(frames[0], frames[2], "Manual UTC must change encoded clock/date: \(codec), \(clipCount) clips")
        }
    }

    private func gpx(_ time: String?) -> Data {
        Data("<gpx version=\"1.1\"><trk><trkseg><trkpt lat=\"0\" lon=\"0\">\(time.map { "<time>\($0)</time>" } ?? "")</trkpt></trkseg></trk></gpx>".utf8)
    }

    private func fitFile(offset: Int? = nil, deviceOffsets: [Int8] = [], activeIndex: UInt8? = 0) -> Data {
        func append32(_ value: UInt32, to data: inout Data) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let start: UInt32 = 1_000_000_000
        var body = Data([0x40, 0, 0, 0, 0, 1, 0, 1, 0, 0, 4])
        body.append(contentsOf: [0x41, 0, 0, 18, 0, 1, 2, 4, 0x86, 1])
        append32(start, to: &body)
        body.append(contentsOf: [0x42, 0, 0, 20, 0, 3, 253, 4, 0x86, 5, 4, 0x86, 3, 1, 2])
        for second: UInt32 in [0, 10] {
            body.append(2); append32(start + second, to: &body)
            append32(second * 300, to: &body); body.append(150)
        }
        if let offset {
            body.append(contentsOf: [0x43, 0, 0, 34, 0, 2, 253, 4, 0x86, 5, 4, 0x86, 3])
            append32(start + 10, to: &body); append32(UInt32(Int(start + 10) + offset), to: &body)
        }
        if !deviceOffsets.isEmpty {
            body.append(contentsOf: [0x44, 0, 0, 2, 0, activeIndex == nil ? 1 : 2, 5, UInt8(deviceOffsets.count), 1])
            if activeIndex != nil { body.append(contentsOf: [0, 1, 2]) }
            body.append(4); body.append(contentsOf: deviceOffsets.map(UInt8.init(bitPattern:)))
            if let activeIndex { body.append(activeIndex) }
        }
        var file = Data([12, 0x10, 0, 8]); append32(UInt32(body.count), to: &file)
        file.append(contentsOf: Array(".FIT".utf8)); file.append(body)
        let crc = FITCRC.compute(file[0..<file.count])
        file.append(UInt8(crc & 255)); file.append(UInt8(crc >> 8))
        return file
    }
}
