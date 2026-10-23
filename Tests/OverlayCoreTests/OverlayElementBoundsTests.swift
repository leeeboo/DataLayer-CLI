import CoreGraphics
import CoreVideo
@testable import OverlayCore
import XCTest

final class OverlayElementBoundsTests: XCTestCase {
    private let size = CGSize(width: 1920, height: 1080)
    private var series: TelemetrySeries {
        TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, date: Date(timeIntervalSince1970: 1_787_000_000), latitude: 35, longitude: 139,
                            altitudeMeters: 100, heartRate: 156, distanceMeters: 0, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 10, date: Date(timeIntervalSince1970: 1_787_000_010), latitude: 35.01, longitude: 139.01,
                            altitudeMeters: 120, heartRate: 165, distanceMeters: 1234, speedMetersPerSecond: 4)
        ])
    }

    func testMetricBoundsGrowWithTextAndUseVisibleSiblingAlignment() throws {
        var pace = element(.pace)
        var heartRate = element(.heartRate)
        heartRate.frame.style.textScale = 4
        heartRate.customization.labelOverride = "A very long custom label"
        heartRate.customization.labelScale = 3
        let renderer = makeRenderer([pace, heartRate])
        let bounds = renderer.elementBounds(videoTime: 5)
        let paceBounds = try XCTUnwrap(bounds[pace.id])
        let heartBounds = try XCTUnwrap(bounds[heartRate.id])
        XCTAssertGreaterThan(paceBounds.width, 160 / size.width)
        XCTAssertEqual(paceBounds.width, heartBounds.width, accuracy: 1e-9)
        XCTAssertGreaterThan(heartBounds.height, 74 / size.height)
        XCTAssertEqual(heartBounds.minY, heartRate.frame.y, accuracy: 1e-9)
        pace.frame.isVisible = false
        let hiddenBounds = try XCTUnwrap(makeRenderer([pace, heartRate]).elementBounds(videoTime: 5)[pace.id])
        XCTAssertGreaterThan(hiddenBounds.width, 0)
    }

    func testDateBoundsIncludeLeftExpansionAndMultilineHeight() throws {
        var date = element(.timeDate)
        date.frame.style.textScale = 4
        date.customization.unitScale = 4
        date.customization.labelOverride = "Date and local clock"
        let bounds = try XCTUnwrap(makeRenderer([date]).elementBounds(videoTime: 5)[date.id])
        XCTAssertLessThan(bounds.minX, date.frame.x)
        XCTAssertEqual(bounds.maxX, date.frame.x + 300 / size.width, accuracy: 1e-9)
        XCTAssertEqual(bounds.minY, date.frame.y, accuracy: 1e-9)
        XCTAssertGreaterThan(bounds.height, 118 / size.height)
    }

    func testProgressBoundsIncludePanelPaddingLargeLabelsAndKnob() throws {
        var progress = element(.topProgress)
        progress.frame.style.textScale = 4
        progress.customization.progressStartScale = 12
        progress.customization.progressCurrentScale = 15
        progress.customization.progressEndScale = 12
        progress.customization.unitOverride = "KILOMETERS"
        progress.customization.progressInsetScale = 0
        let bounds = try XCTUnwrap(makeRenderer([progress]).elementBounds(videoTime: 10)[progress.id])
        XCTAssertLessThan(bounds.minX, progress.frame.x)
        XCTAssertLessThan(bounds.minY, progress.frame.y)
        XCTAssertGreaterThan(bounds.height, 58 / size.height)
    }

    func testBoundsContainRenderedLargeTextAcrossComponentKindsAndMeasurementIsReadOnly() throws {
        for kind in [OverlayComponentID.pace, .weather, .timeDate, .topProgress, .speed, .route, .altitudeProfile] {
            var component = element(kind)
            component.frame.style.textScale = 4
            component.customization.showsPanel = false
            component.customization.labelOverride = "Long custom component label"
            component.customization.unitOverride = "UNIT / KM"
            component.customization.valueScale = 3
            component.customization.labelScale = 3
            component.customization.unitScale = 3
            let renderer = makeRenderer([component])
            let before = try render(renderer)
            let bounds = try XCTUnwrap(renderer.elementBounds(videoTime: 5)[component.id])
            XCTAssertEqual(before, try render(renderer), "Measuring must not change \(kind) rendering")
            let expected = CGRect(x: bounds.minX * size.width, y: bounds.minY * size.height,
                                  width: bounds.width * size.width, height: bounds.height * size.height)
                .insetBy(dx: -2, dy: -2)
            var outsideCount = 0
            for row in 0..<Int(size.height) {
                for x in 0..<Int(size.width) where before[(row * Int(size.width) + x) * 4 + 3] > 8 {
                    if !expected.contains(CGPoint(x: x, y: row)) { outsideCount += 1 }
                }
            }
            XCTAssertEqual(outsideCount, 0, "\(kind) drawing falls outside its measured bounds")
        }
    }

    private func element(_ kind: OverlayComponentID) -> OverlayElement {
        var element = OverlayElement.defaultElement(kind: kind)
        element.frame.x = 0.25
        element.frame.y = 0.3
        element.frame.scale = 1
        element.customization.showsPanel = true
        return element
    }

    private func makeRenderer(_ elements: [OverlayElement]) -> OverlayRenderer {
        OverlayRenderer(series: series, config: .init(size: size, layout: .init(elements: elements), timeZone: TimeZone(secondsFromGMT: 0)!))
    }

    private func render(_ renderer: OverlayRenderer) throws -> Data {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        XCTAssertEqual(CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes, &buffer), kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)
        try renderer.render(videoTime: 5, into: pixelBuffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
        var bytes = Data()
        for row in 0..<Int(size.height) {
            bytes.append(base.advanced(by: row * CVPixelBufferGetBytesPerRow(pixelBuffer)).assumingMemoryBound(to: UInt8.self), count: Int(size.width) * 4)
        }
        return bytes
    }
}
