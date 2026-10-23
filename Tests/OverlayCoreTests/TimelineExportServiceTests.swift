import XCTest
import OverlayCore

final class TimelineExportServiceTests: XCTestCase {
    func testCachedWeatherUsesNearestRecordWithinSixHoursAndPreservesPauses() {
        let date = Date(timeIntervalSince1970: 100_000)
        let series = TelemetrySeries(samples: [TelemetrySample(elapsed: 0, date: date, temperatureCelsius: 17)],
            pausedRanges: [TelemetryPausedRange(start: 0, duration: 2)])
        let records = [
            TimelineWeatherRecord(timestamp: date.addingTimeInterval(6 * 3600), temperatureCelsius: 25, humidityPercent: 60, summary: "Clear"),
            TimelineWeatherRecord(timestamp: date.addingTimeInterval(6 * 3600 + 1), temperatureCelsius: 30, humidityPercent: 90, summary: "Rain")
        ]
        let enriched = TimelineExportService.applyingWeatherRecords(records, to: series)
        XCTAssertEqual(enriched.samples.first?.weatherTemperatureCelsius, 25)
        XCTAssertEqual(enriched.samples.first?.weatherHumidityPercent, 60)
        XCTAssertEqual(enriched.samples.first?.weatherSummary, "Clear")
        XCTAssertEqual(enriched.samples.first?.temperatureCelsius, 17)
        XCTAssertEqual(enriched.pausedRanges, series.pausedRanges)
        XCTAssertEqual(TimelineExportService.applyingWeatherRecords(Array(records.suffix(1)), to: series), series)
        XCTAssertEqual(TimelineExportService.applyingWeatherRecords([], to: series), series)
        let undated = TelemetrySeries(samples: [TelemetrySample(elapsed: 0)])
        XCTAssertEqual(TimelineExportService.applyingWeatherRecords(records, to: undated), undated)
    }

    func testPreflightPreservesValidationOrderAndBuildsWriterSettings() {
        var request = validRequest()
        request.width = 1
        request.height = 721
        XCTAssertEqual(
            TimelineExportService.firstPreflightIssue(
                for: request,
                project: project(),
                availableTelemetryAssetIDs: ["activity"]
            ),
            .outputWidthRange
        )

        request.width = 1920
        XCTAssertEqual(
            TimelineExportService.firstPreflightIssue(
                for: request,
                project: project(),
                availableTelemetryAssetIDs: ["activity"]
            ),
            .outputHeightEven
        )

        request.height = 1080
        XCTAssertNil(
            TimelineExportService.firstPreflightIssue(
                for: request,
                project: project(),
                availableTelemetryAssetIDs: ["activity"]
            )
        )
        XCTAssertEqual(
            TimelineExportService.validatedSettings(for: request),
            TimelineExportSettings(
                width: 1920,
                height: 1080,
                framesPerSecond: 30,
                timelineStart: 0,
                duration: 20,
                averageBitRate: 12_000_000
            )
        )
    }

    func testPreflightReportsTimelineIssueAfterOutputParametersPass() {
        XCTAssertEqual(
            TimelineExportService.firstPreflightIssue(
                for: validRequest(),
                project: project(),
                availableTelemetryAssetIDs: []
            ),
            .timeline(.missingTelemetry(assetID: "activity"))
        )
    }

    func testTelemetrySelectionPrefersLoadedPoolAndFallsBackToActiveSeries() {
        let active = TelemetrySeries(samples: [TelemetrySample(elapsed: 0)])
        let loaded = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0),
            TelemetrySample(elapsed: 10)
        ])
        let resolved = TimelineExportService.telemetrySeries(
            for: project(twoActivities: true),
            loadedSeriesByAssetID: ["activity-2": loaded],
            activeAssetID: "activity",
            activeSeries: active
        )

        XCTAssertEqual(resolved["activity"], active)
        XCTAssertEqual(resolved["activity-2"], loaded)
    }

    func testIndividualClipRangesArePreparedFromRequestedExportWindow() {
        var timeline = project()
        timeline.tracks[0].clips.append(
            TimelineClip(
                id: "video-2",
                assetID: "video",
                timelineStart: 12,
                duration: 8
            )
        )

        XCTAssertEqual(
            TimelineExportService.exportRanges(
                for: timeline,
                request: validRequest(),
                renderScope: .individualClips
            ),
            [
                TimelineExportRange(start: 0, duration: 10),
                TimelineExportRange(start: 12, duration: 8)
            ]
        )
        XCTAssertEqual(
            TimelineExportService.exportRanges(
                for: timeline,
                request: validRequest(),
                renderScope: .singleClip
            ),
            [TimelineExportRange(start: 0, duration: 20)]
        )
    }

    private func validRequest() -> TimelineExportRequest {
        TimelineExportRequest(
            mode: .video,
            codec: .hevc,
            width: 1920,
            height: 1080,
            framesPerSecond: 30,
            timelineStart: 0,
            duration: 20,
            bitRateKbps: 12_000
        )
    }

    private func project(twoActivities: Bool = false) -> TimelineProject {
        var assets = [
            MediaAsset(
                id: "video",
                kind: .video,
                url: URL(fileURLWithPath: "/tmp/video.mov"),
                displayName: "video.mov",
                duration: 30
            ),
            MediaAsset(
                id: "activity",
                kind: .activity,
                url: URL(fileURLWithPath: "/tmp/activity.fit"),
                displayName: "activity.fit",
                duration: 20
            )
        ]
        var overlayClips = [
            TimelineClip(
                id: "activity-1",
                assetID: "activity",
                timelineStart: 0,
                duration: 20
            )
        ]
        if twoActivities {
            assets.append(
                MediaAsset(
                    id: "activity-2",
                    kind: .activity,
                    url: URL(fileURLWithPath: "/tmp/activity-2.fit"),
                    displayName: "activity-2.fit",
                    duration: 20
                )
            )
            overlayClips.append(
                TimelineClip(
                    id: "activity-2",
                    assetID: "activity-2",
                    timelineStart: 20,
                    duration: 20
                )
            )
        }
        return TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: assets,
            tracks: [
                TimelineTrack(
                    id: "video-track",
                    kind: .video,
                    name: "V1",
                    clips: [
                        TimelineClip(
                            id: "video-1",
                            assetID: "video",
                            timelineStart: 0,
                            duration: 10
                        )
                    ]
                ),
                TimelineTrack(
                    id: "overlay-track",
                    kind: .overlay,
                    name: "A1",
                    clips: overlayClips
                )
            ]
        )
    }
}
