#if canImport(CoreMedia)
import CoreMedia
#endif
import Foundation

/// Normalizes the common NTSC frame-rate aliases at runtime while leaving the
/// serialized project value untouched.
public enum FrameRateCanonicalizer {
    /// Common timeline timescale that represents every supported integer and NTSC frame duration
    /// exactly (24/25/30/50/60 and 24000/1001, 30000/1001, 60000/1001).
    public static let timelineTimescale = CMTimeScale(120_000)
    public static let ntsc23_976 = 24_000.0 / 1_001.0
    public static let ntsc29_97 = 30_000.0 / 1_001.0
    public static let ntsc59_94 = 60_000.0 / 1_001.0

    private struct Rate {
        let nominal: Double
        let exact: Double
        let numerator: CMTimeScale
    }

    private static let ntscRates: [Rate] = [
        Rate(nominal: 23.976, exact: ntsc23_976, numerator: 24_000),
        Rate(nominal: 29.97, exact: ntsc29_97, numerator: 30_000),
        Rate(nominal: 59.94, exact: ntsc59_94, numerator: 60_000)
    ]

    /// Returns the exact rational value for a known NTSC rate. Other values
    /// (including invalid values) are returned unchanged for the caller to
    /// validate according to its own configuration rules.
    public static func canonicalize(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        return ntscRates.first {
            abs(value - $0.nominal) < 0.001 || abs(value - $0.exact) < 0.000_001
        }?.exact ?? value
    }

    /// Returns one exact frame duration for a known NTSC rate, or `nil` for a
    /// free-form frame rate.
    public static func exactFrameDuration(for framesPerSecond: Double) -> CMTime? {
        let canonical = canonicalize(framesPerSecond)
        guard let rate = ntscRates.first(where: { canonical == $0.exact }) else {
            return nil
        }
        return CMTime(value: 1_001, timescale: rate.numerator)
    }

    /// Builds a frame duration using the exact NTSC rational where applicable.
    public static func frameDuration(
        for framesPerSecond: Double,
        preferredTimescale: CMTimeScale = 600_000
    ) -> CMTime {
        let canonical = canonicalize(framesPerSecond)
        guard canonical.isFinite, canonical > 0 else {
            return CMTime.invalid
        }
        return exactFrameDuration(for: canonical)
            ?? CMTime(seconds: 1.0 / canonical, preferredTimescale: preferredTimescale)
    }
}
