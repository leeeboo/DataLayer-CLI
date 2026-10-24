#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public enum OverlayDistanceUnit: String, CaseIterable, Codable, Identifiable {
    case meters = "m"
    case kilometers = "km"
    case miles = "mi"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .meters:
            return "Meters (m)"
        case .kilometers:
            return "Kilometers (km)"
        case .miles:
            return "Miles (mi)"
        }
    }

    public var symbol: String { rawValue }

    public var usesImperialMeasurements: Bool { self == .miles }

    public var speedSymbol: String { usesImperialMeasurements ? "MPH" : "KM/H" }

    public var paceSymbol: String { usesImperialMeasurements ? "/MI" : "/KM" }

    public var elevationSymbol: String { usesImperialMeasurements ? "ft" : "m" }

    public var strideLengthSymbol: String { usesImperialMeasurements ? "ft" : "m" }

    public var verticalOscillationSymbol: String { usesImperialMeasurements ? "in" : "CM" }

    public var temperatureSymbol: String { usesImperialMeasurements ? "°F" : "℃" }

    public func distanceValue(meters: Double) -> Double {
        switch self {
        case .meters:
            return meters
        case .kilometers:
            return meters / 1_000
        case .miles:
            return meters / 1_609.344
        }
    }

    public func speedValue(metersPerSecond: Double) -> Double {
        metersPerSecond * (usesImperialMeasurements ? 2.236_936_292_054_4 : 3.6)
    }

    public func paceSeconds(metersPerSecond: Double) -> Double {
        (usesImperialMeasurements ? 1_609.344 : 1_000) / metersPerSecond
    }

    public func elevationValue(meters: Double) -> Double {
        meters * (usesImperialMeasurements ? 3.280_839_895_013_1 : 1)
    }

    public func strideLengthValue(meters: Double) -> Double {
        elevationValue(meters: meters)
    }

    public func verticalOscillationValue(centimeters: Double) -> Double {
        centimeters / (usesImperialMeasurements ? 2.54 : 1)
    }

    public func temperatureValue(celsius: Double) -> Double {
        usesImperialMeasurements ? celsius * 9 / 5 + 32 : celsius
    }

    public func format(meters: Double?) -> String {
        guard let meters, meters.isFinite else { return "--" }
        switch self {
        case .meters:
            return String(format: "%.0f", meters)
        case .kilometers:
            return String(format: "%.2f", meters / 1000)
        case .miles:
            return String(format: "%.2f", distanceValue(meters: meters))
        }
    }
}

public struct OverlayRenderConfig: Equatable {
    public static let millisecondOffsetRange = -999...999
    public static let fitClockOffsetRange = millisecondOffsetRange
    public static let activityOffsetRange = millisecondOffsetRange

    public var size: CGSize
    public var timeSync: TelemetryTimeSync
    /// FIT clock correction applied only to rendered absolute dates, in milliseconds.
    /// The value is normalized to the supported range at configuration consumption time.
    public var fitClockOffsetMilliseconds: Int {
        didSet {
            fitClockOffsetMilliseconds = Self.clampedFitClockOffsetMilliseconds(fitClockOffsetMilliseconds)
        }
    }
    /// Activity/sample correction in milliseconds. Positive values select later activity data
    /// at the current video frame. This never changes the rendered absolute FIT clock.
    public var activityOffsetMilliseconds: Int {
        didSet {
            activityOffsetMilliseconds = Self.clampedActivityOffsetMilliseconds(activityOffsetMilliseconds)
        }
    }
    public var routePointLimit: Int
    public var layout: OverlayLayout
    public var distanceUnit: OverlayDistanceUnit
    public var timeZone: TimeZone
    public var activityTrim: ActivityTrim

    public init(
        size: CGSize,
        timeSync: TelemetryTimeSync = .identity,
        activityOffsetMilliseconds: Int? = nil,
        fitClockOffsetMilliseconds: Int? = nil,
        routePointLimit: Int = 900,
        layout: OverlayLayout = .default,
        distanceUnit: OverlayDistanceUnit = .kilometers,
        timeZone: TimeZone = .current,
        activityTrim: ActivityTrim = .none
    ) {
        self.size = size
        self.timeSync = timeSync
        self.activityOffsetMilliseconds = Self.clampedActivityOffsetMilliseconds(activityOffsetMilliseconds)
        self.fitClockOffsetMilliseconds = Self.clampedFitClockOffsetMilliseconds(fitClockOffsetMilliseconds)
        self.routePointLimit = routePointLimit
        self.layout = layout.sanitized
        self.distanceUnit = distanceUnit
        self.timeZone = timeZone
        self.activityTrim = activityTrim
    }

    public func matchesIgnoringLayout(_ other: OverlayRenderConfig) -> Bool {
        size == other.size
            && timeSync == other.timeSync
            && activityOffsetMilliseconds == other.activityOffsetMilliseconds
            && fitClockOffsetMilliseconds == other.fitClockOffsetMilliseconds
            && routePointLimit == other.routePointLimit
            && distanceUnit == other.distanceUnit
            && timeZone == other.timeZone
            && activityTrim == other.activityTrim
    }

    public static func clampedFitClockOffsetMilliseconds(_ value: Int?) -> Int {
        min(max(value ?? 0, fitClockOffsetRange.lowerBound), fitClockOffsetRange.upperBound)
    }

    public static func clampedActivityOffsetMilliseconds(_ value: Int?) -> Int {
        min(max(value ?? 0, activityOffsetRange.lowerBound), activityOffsetRange.upperBound)
    }

    public func calibratedActivityElapsed(_ baseActivityElapsed: TimeInterval) -> TimeInterval {
        baseActivityElapsed + Double(activityOffsetMilliseconds) / 1_000
    }

    public init(
        size: CGSize,
        telemetryOffset: TimeInterval,
        routePointLimit: Int = 900,
        distanceUnit: OverlayDistanceUnit = .kilometers,
        activityTrim: ActivityTrim = .none
    ) {
        self.init(
            size: size,
            timeSync: .legacyOffset(telemetryOffset),
            routePointLimit: routePointLimit,
            distanceUnit: distanceUnit,
            activityTrim: activityTrim
        )
    }
}
