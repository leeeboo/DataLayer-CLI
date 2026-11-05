import Foundation

public enum VideoTimecodeMode: Equatable {
    case nonDropFrame
    case dropFrame
}

/// Formats frame labels without changing the underlying media time.
public enum VideoTimecode {
    /// Fractional NTSC timelines conventionally use drop-frame labels so the displayed clock
    /// tracks wall time. This selection never changes the underlying frame duration.
    public static func preferredDisplayMode(for framesPerSecond: Double) -> VideoTimecodeMode {
        let rate = FrameRateCanonicalizer.canonicalize(framesPerSecond)
        if abs(rate - FrameRateCanonicalizer.ntsc29_97) < 0.000_001
            || abs(rate - FrameRateCanonicalizer.ntsc59_94) < 0.000_001 {
            return .dropFrame
        }
        return .nonDropFrame
    }

    public static func string(
        at seconds: TimeInterval,
        framesPerSecond: Double,
        mode: VideoTimecodeMode
    ) -> String {
        let rate = FrameRateCanonicalizer.canonicalize(framesPerSecond)
        let safeSeconds = seconds.isFinite ? max(0, seconds) : 0
        let safeRate = rate.isFinite && rate > 0 ? rate : 30
        let frameNumber = Int64(exactly: (safeSeconds * safeRate + 0.000_000_1).rounded(.down)) ?? 0
        return string(frameNumber: frameNumber, framesPerSecond: safeRate, mode: mode)
    }

    public static func string(
        frameNumber: Int64,
        framesPerSecond: Double,
        mode: VideoTimecodeMode
    ) -> String {
        let rate = FrameRateCanonicalizer.canonicalize(framesPerSecond)
        let nominal = UInt64(exactly: max(1, rate.isFinite ? rate.rounded() : 30)) ?? 30
        // Added drop-frame labels can exceed Int64.max even when the source frame fits.
        let safeFrameNumber = UInt64(max(0, frameNumber))
        let isDropFrameRate = abs(rate - FrameRateCanonicalizer.ntsc29_97) < 0.000_001
            || abs(rate - FrameRateCanonicalizer.ntsc59_94) < 0.000_001
        let usesDropFrame = mode == .dropFrame && isDropFrameRate
        let labeledFrameNumber: UInt64

        if usesDropFrame {
            let droppedPerMinute: UInt64 = nominal == 60 ? 4 : 2
            let framesPerMinute = nominal * 60 - droppedPerMinute
            let framesPerTenMinutes = nominal * 600 - droppedPerMinute * 9
            let tenMinuteBlocks = safeFrameNumber / framesPerTenMinutes
            let framesIntoBlock = safeFrameNumber % framesPerTenMinutes
            let completedDroppingMinutes = (max(framesIntoBlock, droppedPerMinute) - droppedPerMinute) / framesPerMinute
            labeledFrameNumber = safeFrameNumber
                + droppedPerMinute * 9 * tenMinuteBlocks
                + droppedPerMinute * completedDroppingMinutes
        } else {
            labeledFrameNumber = safeFrameNumber
        }

        let frames = labeledFrameNumber % nominal
        let totalSeconds = labeledFrameNumber / nominal
        let separator = usesDropFrame ? ";" : ":"
        return String(
            format: "%02llu:%02llu:%02llu%@%02llu",
            totalSeconds / 3_600,
            (totalSeconds / 60) % 60,
            totalSeconds % 60,
            separator,
            frames
        )
    }
}
