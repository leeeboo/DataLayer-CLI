import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// User adjustments after the source's recorded orientation. Flips use the source's own axes,
/// followed by clockwise rotation, matching JianYing's independent mirror and rotation controls.
public struct VideoTransform: Codable, Equatable, Sendable {
    public var quarterTurns: Int {
        didSet { quarterTurns = Self.clamped(quarterTurns) }
    }
    public var flipHorizontal: Bool
    public var flipVertical: Bool

    public static let identity = VideoTransform()

    public init(quarterTurns: Int = 0, flipHorizontal: Bool = false, flipVertical: Bool = false) {
        self.quarterTurns = Self.clamped(quarterTurns)
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    /// Preserve cumulative angles (360°, 450°, …) while rendering an equivalent quarter turn.
    public var rotationDegrees: Int { quarterTurns * 90 }
    public var normalizedQuarterTurns: Int { (quarterTurns % 4 + 4) % 4 }
    private static func clamped(_ turns: Int) -> Int { min(Int.max / 90, max(Int.min / 90, turns)) }

    private enum CodingKeys: String, CodingKey { case quarterTurns, flipHorizontal, flipVertical }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            quarterTurns: try values.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0,
            flipHorizontal: try values.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false,
            flipVertical: try values.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false
        )
    }

    var ffmpegFilters: [String] {
        var filters: [String] = []
        if flipHorizontal { filters.append("hflip") }
        if flipVertical { filters.append("vflip") }
        switch normalizedQuarterTurns {
        case 1: filters.append("transpose=clock")
        case 2: filters += ["hflip", "vflip"]
        case 3: filters.append("transpose=cclock")
        default: break
        }
        return filters
    }
}

#if canImport(CoreGraphics)
extension VideoTransform {
    /// Core Image uses an upward Y axis, so clockwise quarter turns use exact negative rotations.
    /// Normalize after all operations so rotated/mirrored pixels remain inside the output bounds.
    public func sourceTransform(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGAffineTransform {
        let rotation: CGAffineTransform
        switch normalizedQuarterTurns {
        case 1: rotation = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
        case 2: rotation = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
        case 3: rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        default: rotation = .identity
        }
        let transform = preferredTransform
            .concatenating(CGAffineTransform(scaleX: flipHorizontal ? -1 : 1, y: flipVertical ? -1 : 1))
            .concatenating(rotation)
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
    }
}
#endif
