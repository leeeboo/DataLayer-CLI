import Foundation
import OverlayCore

extension CommandLineOptions {
    func resolvingTimelineExportSettings(_ project: TimelineProject) throws -> Self {
        var resolved = self
        let saved = project.exportSettings
        if !specifiedArguments.contains("--export-mode") {
            resolved.exportMode = saved?.exportMode ?? exportMode
        }
        if !specifiedArguments.contains("--codec") {
            let savedCodec = saved?.codec ?? codec
            resolved.codec = savedCodec.exportMode == resolved.exportMode ? savedCodec : resolved.exportMode.defaultCodec
        }
        guard resolved.codec.exportMode == resolved.exportMode else {
            throw CLIError.conflictingArguments("\(resolved.codec.rawValue) cannot be used with --export-mode \(resolved.exportMode.rawValue)")
        }
        if !specifiedArguments.contains("--bitrate"), !specifiedArguments.contains("--bitrate-bps"), let saved {
            resolved.averageBitRate = min(1_000_000, max(1, saved.bitRateKbps)) * 1000
        }
        if let saved {
            resolved.activityTrim = ActivityTrim(
                startSeconds: specifiedArguments.contains("--activity-trim-start") ? activityTrim.startSeconds : saved.activityTrim.startSeconds,
                endSeconds: specifiedArguments.contains("--activity-trim-end") ? activityTrim.endSeconds : saved.activityTrim.endSeconds
            )
            if let end = resolved.activityTrim.endSeconds, end < resolved.activityTrim.startSeconds {
                throw CLIError.conflictingArguments("--activity-trim-end must be greater than or equal to --activity-trim-start")
            }
        }
        return resolved
    }
}

func timelineExportRequest(project: TimelineProject, options: CommandLineOptions) -> TimelineExportRequest {
    let duration = project.duration.isFinite ? min(86_400, max(0, project.duration)) : 0
    let savedStart = project.exportSettings?.timelineStart ?? 0
    let start = min(max(0, duration - 0.1), max(0, savedStart.isFinite ? savedStart : 0))
    let savedEnd = project.exportSettings?.timelineEnd ?? duration
    let end = min(duration, max(min(duration, start + 0.1), savedEnd.isFinite && savedEnd > 0 ? savedEnd : duration))
    return TimelineExportRequest(
        mode: options.exportMode,
        codec: options.codec,
        width: options.width ?? project.outputWidth,
        height: options.height ?? project.outputHeight,
        framesPerSecond: options.framesPerSecond ?? project.framesPerSecond,
        timelineStart: start,
        duration: max(0, end - start),
        bitRateKbps: max(1, options.averageBitRate / 1000)
    )
}

func resolveTimelineBookmark(_ data: Data) -> URL? {
    for options: URL.BookmarkResolutionOptions in [[.withSecurityScope, .withoutUI], [.withoutUI]] {
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return url
        }
    }
    return nil
}
