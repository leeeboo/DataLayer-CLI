import Foundation

public struct TimelineExportRequest: Equatable, Sendable {
    public var mode: OverlayExportMode
    public var codec: OverlayVideoCodec
    public var width: Int
    public var height: Int
    public var framesPerSecond: Double
    public var timelineStart: TimeInterval
    public var duration: TimeInterval?
    public var bitRateKbps: Int

    public init(
        mode: OverlayExportMode,
        codec: OverlayVideoCodec,
        width: Int,
        height: Int,
        framesPerSecond: Double,
        timelineStart: TimeInterval,
        duration: TimeInterval?,
        bitRateKbps: Int
    ) {
        self.mode = mode
        self.codec = codec
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.timelineStart = timelineStart
        self.duration = duration
        self.bitRateKbps = bitRateKbps
    }
}

public struct TimelineExportSettings: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var framesPerSecond: Double
    public var timelineStart: TimeInterval
    public var duration: TimeInterval
    public var averageBitRate: Int

    public init(
        width: Int,
        height: Int,
        framesPerSecond: Double,
        timelineStart: TimeInterval,
        duration: TimeInterval,
        averageBitRate: Int
    ) {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.timelineStart = timelineStart
        self.duration = duration
        self.averageBitRate = averageBitRate
    }
}

public struct TimelineExportRange: Equatable, Sendable {
    public var start: TimeInterval
    public var duration: TimeInterval

    public init(start: TimeInterval, duration: TimeInterval) {
        self.start = start
        self.duration = duration
    }
}

public enum TimelineExportPreflightIssue: Equatable, Sendable {
    case codecExportModeMismatch
    case outputWidthRange
    case outputWidthEven
    case outputHeightRange
    case outputHeightEven
    case frameRateRange
    case sourceDurationRange
    case bitRateRange
    case bitRateTooLarge
    case timeline(TimelineExportValidationIssue)
}

/// Shared timeline export preparation. File selection, overwrite confirmation, entitlement gates,
/// progress UI and task lifecycle remain in each platform session model.
public enum TimelineExportService {
    public static func applyingWeatherRecords(
        _ records: [TimelineWeatherRecord],
        to series: TelemetrySeries
    ) -> TelemetrySeries {
        guard !records.isEmpty else { return series }
        let samples = series.samples.map { sample -> TelemetrySample in
            guard let date = sample.date,
                  let record = records.min(by: {
                      abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
                  }),
                  abs(record.timestamp.timeIntervalSince(date)) <= 6 * 3600 else {
                return sample
            }
            var enriched = sample
            enriched.weatherTemperatureCelsius = record.temperatureCelsius
            enriched.weatherHumidityPercent = record.humidityPercent
            enriched.weatherSummary = record.summary
            return enriched
        }
        return TelemetrySeries(samples: samples, pausedRanges: series.pausedRanges)
    }

    public static func segmentOutputURL(base: URL, index: Int, count: Int) -> URL {
        let fileExtension = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        let width = max(2, String(count).count)
        let name = stem + String(format: "_%0\(width)d", index)
        var url = base.deletingLastPathComponent().appendingPathComponent(name)
        if !fileExtension.isEmpty {
            url = url.appendingPathExtension(fileExtension)
        }
        return url
    }

    public static func telemetrySeries(
        for project: TimelineProject,
        loadedSeriesByAssetID: [String: TelemetrySeries],
        activeAssetID: String? = nil,
        activeSeries: TelemetrySeries? = nil
    ) -> [String: TelemetrySeries] {
        project.tracks
            .filter { $0.kind == .overlay }
            .flatMap(\.clips)
            .reduce(into: [:]) { result, clip in
                if let loaded = loadedSeriesByAssetID[clip.assetID] {
                    result[clip.assetID] = loaded
                } else if clip.assetID == activeAssetID, let activeSeries {
                    result[clip.assetID] = activeSeries
                }
            }
    }

    public static func firstPreflightIssue(
        for request: TimelineExportRequest,
        project: TimelineProject,
        availableTelemetryAssetIDs: Set<String>,
        validatesTimeline: Bool = true
    ) -> TimelineExportPreflightIssue? {
        if let issue = firstParameterIssue(for: request) {
            return issue
        }
        guard let duration = request.duration else {
            return .sourceDurationRange
        }
        if validatesTimeline,
           let issue = project.firstExportValidationIssue(
               mode: request.mode,
               timelineStart: request.timelineStart,
               duration: duration,
               availableTelemetryAssetIDs: availableTelemetryAssetIDs
           ) {
            return .timeline(issue)
        }
        return nil
    }

    public static func validatedSettings(
        for request: TimelineExportRequest
    ) -> TimelineExportSettings? {
        guard firstParameterIssue(for: request) == nil, let duration = request.duration else {
            return nil
        }
        return TimelineExportSettings(
            width: request.width,
            height: request.height,
            framesPerSecond: request.framesPerSecond,
            timelineStart: request.timelineStart,
            duration: duration,
            averageBitRate: request.bitRateKbps * 1000
        )
    }

    public static func exportRanges(
        for project: TimelineProject,
        request: TimelineExportRequest,
        renderScope: TimelineProjectExportSettings.RenderScope
    ) -> [TimelineExportRange] {
        guard let settings = validatedSettings(for: request) else { return [] }
        guard renderScope == .individualClips else {
            return [TimelineExportRange(start: settings.timelineStart, duration: settings.duration)]
        }
        let kind: TimelineTrack.Kind = request.mode == .video ? .video : .overlay
        return project.individualClipExportRanges(
            kind: kind,
            timelineStart: settings.timelineStart,
            duration: settings.duration
        ).map { TimelineExportRange(start: $0.start, duration: $0.duration) }
    }

    private static func firstParameterIssue(
        for request: TimelineExportRequest
    ) -> TimelineExportPreflightIssue? {
        if request.codec.exportMode != request.mode {
            return .codecExportModeMismatch
        }
        if request.width < 2 || request.width > 16_384 {
            return .outputWidthRange
        }
        if request.width % 2 != 0 {
            return .outputWidthEven
        }
        if request.height < 2 || request.height > 16_384 {
            return .outputHeightRange
        }
        if request.height % 2 != 0 {
            return .outputHeightEven
        }
        if !request.framesPerSecond.isFinite
            || request.framesPerSecond < 1
            || request.framesPerSecond > 240 {
            return .frameRateRange
        }
        guard let duration = request.duration,
              request.timelineStart.isFinite,
              request.timelineStart >= 0,
              duration.isFinite,
              duration >= 0.1,
              duration <= 86_400,
              (request.timelineStart + duration).isFinite else {
            return .sourceDurationRange
        }
        if request.bitRateKbps < 1 || request.bitRateKbps > 1_000_000 {
            return .bitRateRange
        }
        if request.bitRateKbps > Int.max / 1000 {
            return .bitRateTooLarge
        }
        return nil
    }
}
