import Foundation

/// A project display/input preference; never changes source timestamps or elapsed sync.
public struct OverlayTimeZone: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public static let activity = OverlayTimeZone("activity")
    public static let system = OverlayTimeZone("system")

    private init(_ value: String) { rawValue = value }

    public init?(rawValue: String) {
        guard rawValue == "activity" || rawValue == "system" || TimeZone(identifier: rawValue) != nil else {
            return nil
        }
        self.rawValue = rawValue
    }

    public func resolve(activityOffsetSeconds: Int?, systemTimeZone: TimeZone = .current) -> TimeZone {
        switch self {
        case .activity:
            return Self.validatedOffset(activityOffsetSeconds).flatMap(TimeZone.init(secondsFromGMT:)) ?? systemTimeZone
        case .system:
            return systemTimeZone
        default:
            return TimeZone(identifier: rawValue) ?? systemTimeZone
        }
    }

    public static func validatedOffset(_ seconds: Int?) -> Int? {
        guard let seconds, (-43_200...50_400).contains(seconds) else { return nil }
        return seconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let selection = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown time zone: \(value)")
        }
        self = selection
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
