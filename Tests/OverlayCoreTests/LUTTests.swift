import CoreImage
@testable import OverlayCore
import XCTest

final class LUTTests: XCTestCase {
    static func cube(invert: Bool = false) -> String {
        "# red varies fastest\nTITLE \"Test LUT\"\nLUT_3D_SIZE 2\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n" +
        (0..<8).map { i in
            let rgb = [i & 1, (i >> 1) & 1, (i >> 2) & 1]
            return rgb.map { String(invert ? 1 - $0 : $0) }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    func testCubeValidationRejectsMalformedOrUnsupportedInput() throws {
        let valid = Self.cube()
        XCTAssertEqual(try CubeLUT(text: valid, name: "Test").dimension, 2)
        XCTAssertEqual(try CubeLUT(text: "\u{FEFF}" + valid.replacingOccurrences(of: "\n", with: "\r\n"), name: "BOM").dimension, 2)
        for invalid in [valid + "\n0 0 0", valid.replacingOccurrences(of: "1 1 1", with: "nan 1 1"),
                        "LUT_3D_SIZE 999999\n", "LUT_1D_SIZE 2\n0 0 0\n1 1 1",
                        valid.replacingOccurrences(of: "DOMAIN_MIN 0 0 0", with: "DOMAIN_MIN -1 0 0"),
                        "LUT_3D_SIZE 2\n0 0 0", "LUT_3D_SIZE 2\nLUT_3D_SIZE 2\n"] {
            XCTAssertThrowsError(try CubeLUT(text: invalid, name: "Bad"))
        }
    }

    func testIdentityInvertAndIntensityPixels() throws {
        let context = CIContext()
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1,
                                          colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        func pixel(_ image: CIImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 4)
            context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: image.extent,
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return bytes
        }
        let original = pixel(image)
        let identity = ClipLUT(lut: try CubeLUT(text: Self.cube(), name: "Identity"))
        let invert = ClipLUT(lut: try CubeLUT(text: Self.cube(invert: true), name: "Invert"))
        let identityPixel = pixel(try identity.applying(to: image))
        let inverted = pixel(try invert.applying(to: image))
        for channel in 0..<3 {
            XCTAssertEqual(Double(identityPixel[channel]), Double(original[channel]), accuracy: 2)
            XCTAssertEqual(Double(inverted[channel]), 255 - Double(original[channel]), accuracy: 3)
        }
        XCTAssertEqual(pixel(try ClipLUT(lut: invert.lut, intensity: 0).applying(to: image)), original)
        let half = pixel(try ClipLUT(lut: invert.lut, intensity: 0.5).applying(to: image))
        for channel in 0..<3 {
            XCTAssertGreaterThan(half[channel], min(original[channel], inverted[channel]))
            XCTAssertLessThan(half[channel], max(original[channel], inverted[channel]))
        }
        XCTAssertEqual(inverted[3], 255)
        let clear = CIImage(color: .clear).cropped(to: image.extent)
        XCTAssertEqual(pixel(try invert.applying(to: clear))[3], 0)
    }

    func testLegacyClipEmbeddedRoundtripAndSplit() throws {
        let legacy = Data(#"{"id":"v","assetID":"a","timelineStart":0,"duration":2}"#.utf8)
        var clip = try JSONDecoder().decode(TimelineClip.self, from: legacy)
        XCTAssertNil(clip.lut)
        clip.lut = ClipLUT(lut: try CubeLUT(text: Self.cube(), name: "Identity"), intensity: 0.6)
        var project = TimelineProject(outputWidth: 64, outputHeight: 64, framesPerSecond: 2, distanceUnit: .kilometers,
                                      tracks: [TimelineTrack(id: "track", kind: .video, name: "V", clips: [clip])])
        XCTAssertEqual(project.splitClips(atTimelineTime: 1), 1)
        XCTAssertEqual(project.tracks[0].clips[1].lut, clip.lut)
        let decoded = try JSONDecoder().decode(TimelineProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded, project)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clip.lut!)) as? [String: Any])
        object["intensity"] = 2
        XCTAssertThrowsError(try JSONDecoder().decode(ClipLUT.self, from: JSONSerialization.data(withJSONObject: object)))
    }
}
