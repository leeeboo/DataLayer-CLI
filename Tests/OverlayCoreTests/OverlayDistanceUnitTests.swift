import OverlayCore
import XCTest

final class OverlayDistanceUnitTests: XCTestCase {
    func testFormatsKilometers() {
        XCTAssertEqual(OverlayDistanceUnit.kilometers.format(meters: 1234.56), "1.23")
    }

    func testFormatsMeters() {
        XCTAssertEqual(OverlayDistanceUnit.meters.format(meters: 1234.56), "1235")
    }

    func testFormatsMiles() {
        XCTAssertEqual(OverlayDistanceUnit.miles.format(meters: 1_609.344), "1.00")
    }

    func testFormatsMissingDistance() {
        XCTAssertEqual(OverlayDistanceUnit.kilometers.format(meters: nil), "--")
        XCTAssertEqual(OverlayDistanceUnit.meters.format(meters: .infinity), "--")
    }

    func testDistanceUnitCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(OverlayDistanceUnit.meters)
        let decoded = try JSONDecoder().decode(OverlayDistanceUnit.self, from: encoded)
        XCTAssertEqual(decoded, .meters)

        XCTAssertEqual(try JSONEncoder().encode(OverlayDistanceUnit.miles), Data("\"mi\"".utf8))
        XCTAssertEqual(try JSONDecoder().decode(OverlayDistanceUnit.self, from: Data("\"km\"".utf8)), .kilometers)
    }

    func testMilesConvertsAllImperialMeasurements() {
        let unit = OverlayDistanceUnit.miles

        XCTAssertTrue(unit.usesImperialMeasurements)
        XCTAssertEqual(unit.speedSymbol, "MPH")
        XCTAssertEqual(unit.paceSymbol, "/MI")
        XCTAssertEqual(unit.elevationSymbol, "ft")
        XCTAssertEqual(unit.strideLengthSymbol, "ft")
        XCTAssertEqual(unit.verticalOscillationSymbol, "in")
        XCTAssertEqual(unit.temperatureSymbol, "°F")
        XCTAssertEqual(unit.distanceValue(meters: 1_609.344), 1, accuracy: 0.000_001)
        XCTAssertEqual(unit.speedValue(metersPerSecond: 1), 2.236_936_292_054_4, accuracy: 0.000_001)
        XCTAssertEqual(unit.paceSeconds(metersPerSecond: 1), 1_609.344, accuracy: 0.000_001)
        XCTAssertEqual(unit.elevationValue(meters: 1), 3.280_839_895_013_1, accuracy: 0.000_001)
        XCTAssertEqual(unit.strideLengthValue(meters: 1), 3.280_839_895_013_1, accuracy: 0.000_001)
        XCTAssertEqual(unit.verticalOscillationValue(centimeters: 2.54), 1, accuracy: 0.000_001)
        XCTAssertEqual(unit.temperatureValue(celsius: 20), 68, accuracy: 0.000_001)
    }

    func testGaugeDistanceUnitOverrideRoundTripsAndOldCustomizationDefaultsToNil() throws {
        let customized = OverlayElementCustomization(distanceUnit: .meters)
        let encoded = try JSONEncoder().encode(customized)
        let decoded = try JSONDecoder().decode(OverlayElementCustomization.self, from: encoded)
        XCTAssertEqual(decoded.distanceUnit, .meters)

        let legacy = try JSONDecoder().decode(
            OverlayElementCustomization.self,
            from: JSONEncoder().encode(OverlayElementCustomization())
        )
        XCTAssertNil(legacy.distanceUnit)
    }
}
