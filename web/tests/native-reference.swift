import Foundation

// Compiled together with the unmodified Core sources to exercise internal corrections too.
private struct ReferenceInput: Decodable {
    var operation: String?
    var samples: [TelemetrySample]?
    var pauses: [TelemetryPausedRange]?
    var queries: [Double]?
    var fitBase64: String?
    var rebuild: Bool?
}

private struct ReferenceQuery: Encodable {
    var wall: Double
    var sample: TelemetrySample
    var date: Date?
    var active: Double
    var display: [String: String]?
}

// Formula copy for metric defaults: OverlayRenderer.metricContent (583–601),
// drawTopProgress (1478–1480), and formatDistance/Decimal/Pace/Weather/Clock (2233–2312).
// Metric conversions/fallbacks: OverlayRenderConfig.OverlayDistanceUnit and OverlayLayout.
private func displayValues(sample: TelemetrySample, date: Date?, series: TelemetrySeries, offset: Int?) -> [String: String] {
    func decimal(_ value: Double?, precision: Int) -> String {
        guard let value, value.isFinite else { return "--" }
        return String(format: "%.\(precision)f", value)
    }
    let pace: String
    if let speed = sample.speedMetersPerSecond, speed > 0.3 {
        let seconds = Int((1000 / speed).rounded())
        pace = String(format: "%d:%02d", seconds / 60, seconds % 60)
    } else {
        pace = "--:--"
    }
    let elapsedSeconds = max(0, Int(floor(sample.elapsed)))
    let temperature = sample.weatherTemperatureCelsius ?? sample.temperatureCelsius
    var values: [String: String] = [
        "pace": pace,
        "heartRate": sample.heartRate.map { "\($0)" } ?? "--",
        "cadence": sample.cadence.map { "\($0)" } ?? "--",
        "calories": sample.totalCalories.map { "\(Int($0.rounded()))" } ?? "--",
        "weatherTemperature": temperature.map { "\(Int(Double($0).rounded()))℃" } ?? "--℃",
        "elapsed": String(format: "%02d:%02d:%02d", elapsedSeconds / 3600, (elapsedSeconds / 60) % 60, elapsedSeconds % 60),
        "clock": "--:--:--", "calendar": "----/--/--"
    ]
    if let date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = offset.flatMap(TimeZone.init(secondsFromGMT:)) ?? .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        values["clock"] = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        values["calendar"] = String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    let totalDistance = series.samples.reversed().first { $0.distanceMeters?.isFinite == true }?.distanceMeters ?? 0
    let displayedTotalDistance = max(totalDistance, sample.distanceMeters ?? 0)
    for precision in 0...3 {
        values["distanceKmPrecision\(precision)"] = decimal(sample.distanceMeters.map { $0 / 1000 }, precision: precision)
        values["totalDistanceKm\(precision)"] = decimal(displayedTotalDistance / 1000, precision: precision)
        values["altitudePrecision\(precision)"] = decimal(sample.altitudeMeters, precision: precision)
        values["ascentPrecision\(precision)"] = decimal(sample.totalAscentMeters, precision: precision)
    }
    return values
}

private struct ReferenceOutput: Encodable {
    var samples: [TelemetrySample]
    var pausedRanges: [TelemetryPausedRange]?
    var bounds: GeoBounds?
    var duration: Double?
    var activeDuration: Double?
    var activityStartDate: Date?
    var sport: String?
    var timeZoneOffsetSeconds: Int?
    var queries: [ReferenceQuery]?

    init(samples: [TelemetrySample]) { self.samples = samples }

    init(series: TelemetrySeries, queries: [Double], activity: ParsedActivity? = nil, display: Bool = false) {
        samples = series.samples
        pausedRanges = series.pausedRanges
        bounds = series.bounds
        duration = series.duration
        activeDuration = series.activeDuration
        activityStartDate = series.activityStartDate
        sport = activity?.sport?.rawValue
        timeZoneOffsetSeconds = activity?.timeZoneOffsetSeconds
        self.queries = queries.map { wall in
            let sample = series.sample(at: wall), date = series.date(atElapsed: wall)
            return ReferenceQuery(wall: wall, sample: sample, date: date,
                active: series.activeElapsed(forWallElapsed: wall),
                display: display ? displayValues(sample: sample, date: date, series: series, offset: activity?.timeZoneOffsetSeconds) : nil)
        }
    }
}

@main
private enum NativeReference {
    static func main() throws {
        let display = CommandLine.arguments.contains("--display")
        let arguments = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--display" }
        guard arguments.count >= 2 else {
            throw NSError(domain: "native-reference input.json output.json | --fit input.fit output.json [queries.json] [--display]", code: 1)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let output: ReferenceOutput
        let destination: String
        if arguments[0] == "--fit" {
            guard arguments.count >= 3 else { throw NSError(domain: "Missing FIT output path", code: 1) }
            let activity = try FITParser().parseActivity(url: URL(fileURLWithPath: arguments[1]))
            let queries = arguments.count > 3
                ? try decoder.decode([Double].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[3])))
                : [0, activity.series.duration]
            output = ReferenceOutput(series: activity.series, queries: queries, activity: activity, display: display)
            destination = arguments[2]
        } else {
            let input = try decoder.decode(ReferenceInput.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[0])))
            if input.operation == "fit" {
                guard let encoded = input.fitBase64, let data = Data(base64Encoded: encoded) else {
                    throw NSError(domain: "Invalid FIT base64", code: 1)
                }
                let activity = try FITParser().parseActivity(data: data)
                output = ReferenceOutput(series: activity.series, queries: input.queries ?? [], activity: activity, display: display)
            } else if input.operation == "correction" {
                output = ReferenceOutput(samples: TelemetrySeries.correctingRunningDecelerations(in: input.samples ?? []))
            } else {
                var series = TelemetrySeries(samples: input.samples ?? [], pausedRanges: input.pauses ?? [])
                if input.operation == "altitude" { series = series.applyingQuantizedAltitudeDisplaySmoothing() }
                if input.rebuild == true { series = TelemetrySeries(samples: series.samples, pausedRanges: series.pausedRanges) }
                output = ReferenceOutput(series: series, queries: input.queries ?? [], display: display)
            }
            destination = arguments[1]
        }
        try encoder.encode(output).write(to: URL(fileURLWithPath: destination), options: .atomic)
    }
}
