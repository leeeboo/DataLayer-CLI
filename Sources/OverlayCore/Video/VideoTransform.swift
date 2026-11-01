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
    public private(set) var scaleX: Double
    public private(set) var scaleY: Double
    public var isScaleLocked: Bool
    /// JianYing coordinates: ±1 offsets the center by half the canvas dimension; positive Y is up.
    public var positionX: Double {
        didSet { positionX = Self.position(positionX) }
    }
    public var positionY: Double {
        didSet { positionY = Self.position(positionY) }
    }

    /// Limits for values entered directly. A locked secondary axis can extend past these limits.
    public static let editableScaleRange = 0.01...99.99

    public static let identity = VideoTransform()

    public init(quarterTurns: Int = 0, flipHorizontal: Bool = false, flipVertical: Bool = false,
                scaleX: Double = 1, scaleY: Double = 1, isScaleLocked: Bool = true,
                positionX: Double = 0, positionY: Double = 0) {
        self.quarterTurns = Self.clamped(quarterTurns)
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.scaleX = Self.scale(scaleX)
        self.scaleY = Self.scale(scaleY)
        self.isScaleLocked = isScaleLocked
        self.positionX = Self.position(positionX)
        self.positionY = Self.position(positionY)
    }

    public var hasScaleOrPositionAdjustments: Bool { scaleX != 1 || scaleY != 1 || positionX != 0 || positionY != 0 }

    public mutating func setScaleX(_ value: Double) {
        let next = Self.enteredScale(value)
        if isScaleLocked { scaleY = Self.scale(scaleY * next / scaleX) }
        scaleX = next
    }

    public mutating func setScaleY(_ value: Double) {
        let next = Self.enteredScale(value)
        if isScaleLocked { scaleX = Self.scale(scaleX * next / scaleY) }
        scaleY = next
    }

    public mutating func resetScaleAndPosition() {
        scaleX = 1
        scaleY = 1
        positionX = 0
        positionY = 0
        isScaleLocked = true
    }

    private static func scale(_ value: Double) -> Double { value.isFinite ? min(1_000_000, max(0.000001, value)) : 1 }
    private static func enteredScale(_ value: Double) -> Double {
        value.isFinite ? min(editableScaleRange.upperBound, max(editableScaleRange.lowerBound, value)) : 1
    }
    private static func position(_ value: Double) -> Double { value.isFinite ? min(1000, max(-1000, value)) : 0 }

    /// Preserve cumulative angles (360°, 450°, …) while rendering an equivalent quarter turn.
    public var rotationDegrees: Int { quarterTurns * 90 }
    public var normalizedQuarterTurns: Int { (quarterTurns % 4 + 4) % 4 }
    private static func clamped(_ turns: Int) -> Int { min(Int.max / 90, max(Int.min / 90, turns)) }

    private enum CodingKeys: String, CodingKey {
        case quarterTurns, flipHorizontal, flipVertical, scaleX, scaleY, isScaleLocked, positionX, positionY
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            quarterTurns: try values.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0,
            flipHorizontal: try values.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false,
            flipVertical: try values.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false,
            scaleX: try values.decodeIfPresent(Double.self, forKey: .scaleX) ?? 1,
            scaleY: try values.decodeIfPresent(Double.self, forKey: .scaleY) ?? 1,
            isScaleLocked: try values.decodeIfPresent(Bool.self, forKey: .isScaleLocked) ?? true,
            positionX: try values.decodeIfPresent(Double.self, forKey: .positionX) ?? 0,
            positionY: try values.decodeIfPresent(Double.self, forKey: .positionY) ?? 0
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

    /// Inverse-map onto a fixed canvas for spatial edits, so even extreme zoom never allocates
    /// an oversized intermediate video frame. The common rotation-only path keeps fast filters.
    func ffmpegGeometryFilters(width: Int, height: Int) -> [String] {
        guard hasScaleOrPositionAdjustments else {
            return ffmpegFilters + ["pad=w='max(iw,\(width))':h='max(ih,\(height))':x=(ow-iw)/2:y=(oh-ih)/2:color=black",
                                    "crop=\(width):\(height):(iw-ow)/2:(ih-oh)/2"]
        }
        let x = "(X+0.5-W/2-(\(positionX)*W/2))"
        let y = "(Y+0.5-H/2+(\(positionY)*H/2))"
        let unrotated: (String, String)
        switch normalizedQuarterTurns {
        case 1: unrotated = (y, "(-\(x))")
        case 2: unrotated = ("(-\(x))", "(-\(y))")
        case 3: unrotated = ("(-\(y))", x)
        default: unrotated = (x, y)
        }
        let sourceX = "(\(flipHorizontal ? -1 : 1)*\(unrotated.0)/\(scaleX)+W/2-0.5)"
        let sourceY = "(\(flipVertical ? -1 : 1)*\(unrotated.1)/\(scaleY)+H/2-0.5)"
        let inside = "between(\(sourceX),0,W-1)*between(\(sourceY),0,H-1)"
        let channels = ["r", "g", "b"].map { channel in
            "\(channel)='if(\(inside),\(channel)(\(sourceX),\(sourceY)),0)'"
        }.joined(separator: ":")
        let alpha = "a='if(\(inside),alpha(\(sourceX),\(sourceY)),0)'"
        return ["pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2:black", "format=gbrap16le", "geq=\(channels):\(alpha):interpolation=bilinear"]
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
            .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
            .concatenating(CGAffineTransform(scaleX: flipHorizontal ? -1 : 1, y: flipVertical ? -1 : 1))
            .concatenating(rotation)
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
    }
}
#endif
