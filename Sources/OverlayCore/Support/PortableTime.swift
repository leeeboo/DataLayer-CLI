#if os(Linux) || os(Windows)
import Foundation

// Keep the existing rational frame-timing implementation shared with CoreMedia platforms.
public typealias CMTimeScale = Int32
public typealias CMTimeValue = Int64
public struct CMTime: Equatable {
    public let value: Int64
    public let timescale: Int32
    public init(value: Int64, timescale: Int32) { self.value = value; self.timescale = timescale }
    public init(seconds: Double, preferredTimescale: Int32) {
        let scaled = (seconds * Double(preferredTimescale)).rounded()
        if scaled.isFinite, scaled >= Double(Int64.min), scaled < Double(Int64.max), preferredTimescale > 0 {
            self.init(value: Int64(scaled), timescale: preferredTimescale)
        } else { self = .invalid }
    }
    public static let invalid = CMTime(value: 0, timescale: 0)
    public var seconds: Double { timescale > 0 ? Double(value) / Double(timescale) : .nan }
}
public func CMTimeGetSeconds(_ time: CMTime) -> Double { time.seconds }
#endif
