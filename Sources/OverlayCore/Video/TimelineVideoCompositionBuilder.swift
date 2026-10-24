#if canImport(AVFoundation)
import AVFoundation
import Foundation

private struct TimelineColorParameters {
    var sourceInfo: VideoColorInfo?
    var settings: VideoColorSettings?
    var lut: ClipLUT?
}

/// Assembles an `AVMutableComposition` from a timeline's resolved visible video segments: every
/// segment's video and audio land at its timeline position, and uncovered ranges stay empty so
/// playback and sample reading produce black frames and silence there.
///
/// Shared by `TimelineVideoWriter` (export) and the studio preview player so both read the same
/// clip geometry the same way.
public enum TimelineVideoCompositionBuilder {
    public static func make(
        project: TimelineProject,
        videoClips: [TimelineClip],
        requiredEnd: TimeInterval,
        renderSize requestedRenderSize: CGSize? = nil,
        framesPerSecond requestedFramesPerSecond: Double? = nil
    ) throws -> (
        composition: AVMutableComposition,
        videoRanges: [CMTimeRange],
        videoComposition: AVMutableVideoComposition
    ) {
        let composition = AVMutableComposition()
        let timescale = FrameRateCanonicalizer.timelineTimescale
        var videoRanges: [CMTimeRange] = []
        var videoInstructions: [AVMutableVideoCompositionInstruction] = []
        var colorByInstruction: [ObjectIdentifier: TimelineColorParameters] = [:]
        let renderSize = sanitizedRenderSize(
            requestedRenderSize ?? CGSize(width: project.outputWidth, height: project.outputHeight)
        )
        let framesPerSecond = sanitizedFramesPerSecond(
            requestedFramesPerSecond ?? project.framesPerSecond
        )

        for clip in videoClips {
            guard let videoAsset = project.asset(id: clip.assetID), videoAsset.kind == .video else {
                throw OverlayVideoError.invalidConfiguration("Timeline video clip references a missing video asset.")
            }
            let sourceAsset = AVURLAsset(url: videoAsset.url)
            guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
                throw OverlayVideoError.unreadableVideo("No video track found in \(videoAsset.url.path).")
            }
            // Resolved visible clips are serial, not simultaneous. Reuse a compatible
            // composition track so AVFoundation does not initialize one decoder pipeline
            // per edit when the reader prepares the first frame of a long timeline.
            guard let compositionVideoTrack = composition.mutableTrack(compatibleWith: sourceVideoTrack)
                ?? composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                throw OverlayVideoError.writerFailed("Could not create timeline video composition track.")
            }

            let requestedSourceDuration = CMTime(seconds: clip.duration, preferredTimescale: timescale)
            let sourceRange = try availableVideoSourceRange(
                for: clip,
                videoTrack: sourceVideoTrack,
                preferredTimescale: timescale
            )

            let destinationStart = CMTime(seconds: clip.timelineStart, preferredTimescale: timescale)
            try compositionVideoTrack.insertTimeRange(
                sourceRange,
                of: sourceVideoTrack,
                at: destinationStart
            )
            videoRanges.append(CMTimeRange(start: destinationStart, duration: sourceRange.duration))
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            layerInstruction.setTransform(
                aspectFitTransform(
                    naturalSize: sourceVideoTrack.naturalSize,
                    preferredTransform: sourceVideoTrack.preferredTransform,
                    renderSize: renderSize
                ),
                at: destinationStart
            )
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: destinationStart, duration: sourceRange.duration)
            instruction.layerInstructions = [layerInstruction]
            instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
            videoInstructions.append(instruction)
            colorByInstruction[ObjectIdentifier(instruction)] = TimelineColorParameters(
                sourceInfo: videoAsset.colorInfo
                    ?? sourceVideoTrack.formatDescriptions.first
                        .flatMap { VideoColorInfo.read(from: $0 as! CMFormatDescription) },
                settings: clip.colorSettings,
                lut: clip.lut
            )

            for sourceAudioTrack in sourceAsset.tracks(withMediaType: .audio) {
                let audioStart = CMTimeAdd(
                    sourceAudioTrack.timeRange.start,
                    CMTime(seconds: clip.sourceIn, preferredTimescale: timescale)
                )
                let audioEnd = CMTimeAdd(audioStart, requestedSourceDuration)
                let availableAudioEnd = CMTimeRangeGetEnd(sourceAudioTrack.timeRange)
                let audioDuration = minTime(requestedSourceDuration, CMTimeSubtract(availableAudioEnd, audioStart))
                guard audioStart >= sourceAudioTrack.timeRange.start,
                      audioEnd > sourceAudioTrack.timeRange.start,
                      audioDuration > .zero else {
                    continue
                }
                let destinationRange = CMTimeRange(start: destinationStart, duration: audioDuration)
                // Resolved video clips do not overlap, so compatible source audio can share a
                // composition track without changing clip timing or filling intentional gaps.
                // A source may contain parallel audio tracks, though, which must remain
                // separate when they target the same timeline interval.
                let compatibleTrack = composition.mutableTrack(compatibleWith: sourceAudioTrack)
                let reusableTrack = compatibleTrack.flatMap { track in
                    audioTrack(track, hasSegmentOverlapping: destinationRange) ? nil : track
                }
                guard let compositionAudioTrack = reusableTrack
                    ?? composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) else {
                    continue
                }
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: audioStart, duration: audioDuration),
                    of: sourceAudioTrack,
                    at: destinationStart
                )
            }
        }

        let requiredEndTime = CMTime(seconds: requiredEnd, preferredTimescale: timescale)
        if composition.duration < requiredEndTime {
            composition.insertEmptyTimeRange(
                CMTimeRange(
                    start: composition.duration,
                    duration: CMTimeSubtract(requiredEndTime, composition.duration)
                )
            )
        }


        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = FrameRateCanonicalizer.frameDuration(
            for: framesPerSecond,
            preferredTimescale: 60_000
        )
        videoComposition.instructions = instructionsFillingGaps(
            videoInstructions,
            requiredEnd: requiredEndTime
        )

        if !videoClips.isEmpty {
            videoComposition.customVideoCompositorClass = LUTVideoCompositor.self
            videoComposition.instructions = videoComposition.instructions.compactMap { instruction in
                guard let instruction = instruction as? AVMutableVideoCompositionInstruction else { return nil }
                let layer = instruction.layerInstructions.first
                var transform = CGAffineTransform.identity
                layer?.getTransformRamp(for: instruction.timeRange.start, start: &transform, end: nil, timeRange: nil)
                let color = colorByInstruction[ObjectIdentifier(instruction)]
                return LUTVideoInstruction(
                    timeRange: instruction.timeRange,
                    trackID: layer?.trackID,
                    transform: transform,
                    sourceInfo: color?.sourceInfo,
                    colorSettings: color?.settings,
                    lut: color?.lut
                )
            }
        }
        return (composition, videoRanges, videoComposition)
    }

    /// Creates a source-time-preserving custom composition for preview and high-precision frame extraction.
    public static func makeSingleAssetVideoComposition(
        asset: AVAsset,
        trackID: CMPersistentTrackID,
        timeRange: CMTimeRange,
        transform: CGAffineTransform,
        renderSize: CGSize,
        sourceInfo: VideoColorInfo?,
        settings: VideoColorSettings?,
        lut: ClipLUT?
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let trackRate = asset.tracks(withMediaType: .video)
            .first(where: { $0.trackID == trackID })?.nominalFrameRate
        let frameRate = trackRate.flatMap { $0 > 0 ? Double($0) : nil } ?? 30
        videoComposition.frameDuration = FrameRateCanonicalizer.frameDuration(
            for: frameRate,
            preferredTimescale: 60_000
        )
        videoComposition.instructions = [LUTVideoInstruction(
            timeRange: timeRange,
            trackID: trackID,
            transform: transform,
            sourceInfo: sourceInfo ?? asset.tracks(withMediaType: .video)
                .first(where: { $0.trackID == trackID })?
                .formatDescriptions.first.flatMap { VideoColorInfo.read(from: $0 as! CMFormatDescription) },
            colorSettings: settings,
            lut: lut
        )]
        videoComposition.customVideoCompositorClass = LUTVideoCompositor.self
        return videoComposition
    }

    /// A container's duration can legitimately extend past its video track (for example when
    /// audio or edit-list metadata has a slightly longer tail). Timeline clips use the container
    /// duration, so clamp only the media range to the actual video track and leave the remainder
    /// as the timeline's normal black gap.
    static func availableVideoSourceRange(
        for clip: TimelineClip,
        videoTrack: AVAssetTrack,
        preferredTimescale: CMTimeScale
    ) throws -> CMTimeRange {
        let trackStart = videoTrack.timeRange.start
        let trackEnd = CMTimeRangeGetEnd(videoTrack.timeRange)
        let sourceStart = CMTimeAdd(
            trackStart,
            CMTime(seconds: clip.sourceIn, preferredTimescale: preferredTimescale)
        )
        let requestedDuration = CMTime(seconds: clip.duration, preferredTimescale: preferredTimescale)
        let availableDuration = CMTimeSubtract(trackEnd, sourceStart)
        guard CMTimeCompare(sourceStart, trackStart) >= 0,
              CMTimeCompare(sourceStart, trackEnd) < 0,
              CMTimeCompare(requestedDuration, .zero) > 0,
              CMTimeCompare(availableDuration, .zero) > 0 else {
            throw OverlayVideoError.invalidConfiguration("Timeline video clip extends past its source video duration.")
        }
        return CMTimeRange(
            start: sourceStart,
            duration: minTime(requestedDuration, availableDuration)
        )
    }

    static func aspectFitTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let scale = min(
            renderSize.width / max(1, displaySize.width),
            renderSize.height / max(1, displaySize.height)
        )
        let x = -transformedRect.minX * scale + (renderSize.width - displaySize.width * scale) / 2
        let y = -transformedRect.minY * scale + (renderSize.height - displaySize.height * scale) / 2
        return preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
    }

    private static func instructionsFillingGaps(
        _ videoInstructions: [AVMutableVideoCompositionInstruction],
        requiredEnd: CMTime
    ) -> [AVVideoCompositionInstructionProtocol] {
        let sorted = videoInstructions.sorted { $0.timeRange.start < $1.timeRange.start }
        var result: [AVVideoCompositionInstructionProtocol] = []
        var cursor = CMTime.zero
        for instruction in sorted {
            if instruction.timeRange.start > cursor {
                result.append(blackInstruction(
                    start: cursor,
                    duration: CMTimeSubtract(instruction.timeRange.start, cursor)
                ))
            }
            result.append(instruction)
            cursor = maxTime(cursor, CMTimeRangeGetEnd(instruction.timeRange))
        }
        if requiredEnd > cursor {
            result.append(blackInstruction(start: cursor, duration: CMTimeSubtract(requiredEnd, cursor)))
        }
        return result
    }

    private static func blackInstruction(start: CMTime, duration: CMTime) -> AVMutableVideoCompositionInstruction {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: start, duration: duration)
        instruction.layerInstructions = []
        instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
        return instruction
    }

    private static func sanitizedRenderSize(_ size: CGSize) -> CGSize {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return CGSize(width: 1_920, height: 1_080)
        }
        return size
    }

    private static func sanitizedFramesPerSecond(_ value: Double) -> Double {
        let finiteValue = value.isFinite && value > 0 ? value : 30
        return FrameRateCanonicalizer.canonicalize(finiteValue)
    }

    private static func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }

    private static func audioTrack(
        _ track: AVCompositionTrack,
        hasSegmentOverlapping destinationRange: CMTimeRange
    ) -> Bool {
        track.segments.contains { segment in
            CMTimeRangeGetIntersection(
                segment.timeMapping.target,
                otherRange: destinationRange
            ).duration > .zero
        }
    }

    private static func maxTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) >= 0 ? lhs : rhs
    }
}

#endif
