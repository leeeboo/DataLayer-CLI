import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
@testable import OverlayCore
import XCTest

final class VideoColorPipelineTests: XCTestCase {
    func testReadsOnlyPresentFormatDescriptionColorLabels() throws {
        let rec709 = try makeDescription([
            kCMFormatDescriptionExtension_ColorPrimaries as String: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCMFormatDescriptionExtension_TransferFunction as String: kCVImageBufferTransferFunction_ITU_R_709_2,
            kCMFormatDescriptionExtension_YCbCrMatrix as String: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            kCMFormatDescriptionExtension_FullRangeVideo as String: kCFBooleanTrue as Any
        ])
        let sRGB = try makeDescription([
            kCMFormatDescriptionExtension_ColorPrimaries as String: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCMFormatDescriptionExtension_TransferFunction as String: kCVImageBufferTransferFunction_sRGB
        ])
        let hlg = try makeDescription([
            kCMFormatDescriptionExtension_ColorPrimaries as String: kCVImageBufferColorPrimaries_ITU_R_2020,
            kCMFormatDescriptionExtension_TransferFunction as String: kCVImageBufferTransferFunction_ITU_R_2100_HLG,
            kCMFormatDescriptionExtension_YCbCrMatrix as String: kCVImageBufferYCbCrMatrix_ITU_R_2020
        ])
        let pq = try makeDescription([
            kCMFormatDescriptionExtension_ColorPrimaries as String: kCVImageBufferColorPrimaries_ITU_R_2020,
            kCMFormatDescriptionExtension_TransferFunction as String: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
            kCMFormatDescriptionExtension_YCbCrMatrix as String: kCVImageBufferYCbCrMatrix_ITU_R_2020
        ])
        let appleLog = try makeDescription(["LogTransferFunction": "com.apple.rec2020.apple-log"])
        let appleLog2 = try makeDescription(["LogTransferFunction": "com.apple.apple-wide-gamut.apple-log"])
        let missing = try makeDescription([:])

        let rec709Info = try XCTUnwrap(VideoColorInfo.read(from: rec709))
        XCTAssertEqual(rec709Info.detectedInput, .rec709)
        XCTAssertEqual(rec709Info.isFullRange, true)
        XCTAssertFalse(rec709Info.isAssumed)
        XCTAssertEqual(VideoColorInfo.read(from: sRGB)?.detectedInput, .sRGB)
        XCTAssertEqual(VideoColorInfo.read(from: hlg)?.detectedInput, .hlg)
        XCTAssertEqual(VideoColorInfo.read(from: pq)?.detectedInput, .pq)
        XCTAssertEqual(VideoColorInfo.read(from: appleLog)?.detectedInput, .log)
        XCTAssertEqual(VideoColorInfo.read(from: appleLog2)?.detectedInput, .log)
        XCTAssertNil(VideoColorInfo.read(from: missing))

        let unrecognized = try makeDescription([
            kCMFormatDescriptionExtension_ColorPrimaries as String: kCVImageBufferColorPrimaries_ITU_R_2020,
            kCMFormatDescriptionExtension_TransferFunction as String: kCVImageBufferTransferFunction_ITU_R_709_2
        ])
        let unknownInfo = try XCTUnwrap(VideoColorInfo.read(from: unrecognized))
        XCTAssertNil(unknownInfo.detectedInput)
        XCTAssertTrue(unknownInfo.isAssumed)
        XCTAssertEqual(unknownInfo.colorPrimaries, kCVImageBufferColorPrimaries_ITU_R_2020 as String)
    }

    func testLegacyAndNewColorProjectPersistenceAndSplit() throws {
        let legacyClipJSON = Data(#"{"id":"old","assetID":"video","timelineStart":0,"duration":2}"#.utf8)
        let legacyClip = try JSONDecoder().decode(TimelineClip.self, from: legacyClipJSON)
        XCTAssertNil(legacyClip.colorSettings)

        let lut = try CubeLUT(text: scaledCube(0.5), name: "Log to 709")
        let legacyLUTData = try JSONEncoder().encode(ClipLUT(lut: lut))
        var legacyLUTObject = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyLUTData) as? [String: Any])
        legacyLUTObject.removeValue(forKey: "usage")
        let decodedLegacyLUT = try JSONDecoder().decode(
            ClipLUT.self,
            from: JSONSerialization.data(withJSONObject: legacyLUTObject)
        )
        XCTAssertEqual(decodedLegacyLUT.usage, .creative)

        for version in 1...3 {
            let oldProject = TimelineProject(
                outputWidth: 32,
                outputHeight: 32,
                framesPerSecond: 30,
                distanceUnit: .kilometers,
                schemaVersion: version
            )
            let roundTrip = try JSONDecoder().decode(TimelineProject.self, from: JSONEncoder().encode(oldProject))
            XCTAssertEqual(roundTrip.schemaVersion, version)
        }

        let info = VideoColorInfo(
            colorPrimaries: kCVImageBufferColorPrimaries_ITU_R_2020 as String,
            transferFunction: kCVImageBufferTransferFunction_ITU_R_2100_HLG as String,
            yCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_2020 as String,
            isFullRange: true
        )
        let asset = MediaAsset(
            id: "video",
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/source.mov"),
            displayName: "source.mov",
            duration: 2,
            colorInfo: info
        )
        let clip = TimelineClip(
            id: "clip",
            assetID: asset.id,
            timelineStart: 0,
            duration: 2,
            lut: ClipLUT(lut: lut, intensity: 0.25, usage: .sourceConversion),
            colorSettings: VideoColorSettings(input: .automatic)
        )
        let project = TimelineProject(
            outputWidth: 32,
            outputHeight: 32,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [asset],
            tracks: [TimelineTrack(id: "track", kind: .video, name: "V1", clips: [clip])],
            schemaVersion: 3
        )
        let data = try JSONEncoder().encode(project)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 4)

        var decoded = try JSONDecoder().decode(TimelineProject.self, from: data)
        XCTAssertEqual(decoded.assets.first?.colorInfo, info)
        XCTAssertEqual(decoded.tracks[0].clips[0].colorSettings, clip.colorSettings)
        XCTAssertEqual(decoded.tracks[0].clips[0].lut?.usage, .sourceConversion)
        XCTAssertEqual(decoded.tracks[0].clips[0].lut?.intensity, 0.25)
        XCTAssertEqual(decoded.splitClips(atTimelineTime: 1), 1)
        XCTAssertEqual(decoded.tracks[0].clips.map(\.colorSettings), [clip.colorSettings, clip.colorSettings])
        XCTAssertEqual(decoded.tracks[0].clips.map(\.lut), [clip.lut, clip.lut])
    }

    func testSourceConversionLUTUsesEncodedMidgrayAtFullStrength() throws {
        let source = try makeHalfBuffer([(0.5, 0.5, 0.5, 1)])
        let cube = try CubeLUT(text: scaledCube(0.5), name: "Half")
        let lut = ClipLUT(lut: cube, usage: .sourceConversion)
        XCTAssertEqual(lut.intensity, 1)

        let processed = try VideoColorPipeline.process(
            pixelBuffer: source,
            sourceInfo: nil,
            settings: nil,
            lut: lut
        )
        let output = try render709Half(processed)
        let pixel = readHalfBuffer(output)[0]
        XCTAssertEqual(pixel.0, 0.25, accuracy: 0.015)
        XCTAssertEqual(pixel.1, 0.25, accuracy: 0.015)
        XCTAssertEqual(pixel.2, 0.25, accuracy: 0.015)
        XCTAssertEqual(pixel.3, 1, accuracy: 0.001)

        let tagged = CIImage(cvPixelBuffer: source, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let taggedResult = try VideoColorPipeline.process(image: tagged, sourceInfo: nil, settings: nil, lut: lut)
        XCTAssertEqual(readHalfBuffer(try render709Half(taggedResult))[0].0, 0.25, accuracy: 0.015)
    }

    func testLUTIntensityRemainsAdjustableForConversionAndLogInput() throws {
        let source = try makeHalfBuffer([(0.5, 0.5, 0.5, 1)])
        let cube = try CubeLUT(text: scaledCube(0.5), name: "Half")
        for usage in [VideoLUTUsage.creative, .sourceConversion] {
            XCTAssertEqual(ClipLUT(lut: cube, usage: usage).intensity, 1)
            let lut = ClipLUT(lut: cube, intensity: 0.5, usage: usage)
            let restored = try JSONDecoder().decode(ClipLUT.self, from: JSONEncoder().encode(lut))
            XCTAssertEqual(restored.intensity, 0.5)
            let output = try VideoColorPipeline.process(
                pixelBuffer: source, sourceInfo: nil,
                settings: VideoColorSettings(input: .log), lut: restored
            )
            XCTAssertEqual(readHalfBuffer(try render709Half(output))[0].0, 0.375, accuracy: 0.015)
        }
    }

    func testUnknownHDRGamutFailsAndLogRequiresATechnicalLUT() throws {
        let source = try makeHalfBuffer([(0.5, 0.5, 0.5, 1)])
        let unsupportedHDR = VideoColorInfo(
            colorPrimaries: kCVImageBufferColorPrimaries_P3_D65 as String,
            transferFunction: kCVImageBufferTransferFunction_ITU_R_2100_HLG as String,
            yCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String
        )
        XCTAssertThrowsError(try VideoColorPipeline.process(
            pixelBuffer: source,
            sourceInfo: unsupportedHDR,
            settings: nil,
            lut: nil
        )) { error in
            guard let failure = error as? VideoColorPipeline.Failure,
                  case .unsupportedHDRSourceColorSpace = failure else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let log = VideoColorInfo(logTransferFunction: "com.apple.rec2020.apple-log")
        XCTAssertThrowsError(try VideoColorPipeline.process(
            pixelBuffer: source,
            sourceInfo: log,
            settings: nil,
            lut: nil
        )) { error in
            guard let failure = error as? CubeLUT.Failure,
                  case .requiresSourceConversionLUT = failure else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testEmbeddedImageICCIsUsedAsTheSourceProfile() throws {
        let bytes = Data([128, 128, 128, 255])
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let rec709Gamma = try XCTUnwrap(CGColorSpace(name: CGColorSpace.itur_709))
        let sRGBImage = CIImage(bitmapData: bytes, bytesPerRow: 4, size: CGSize(width: 1, height: 1), format: .RGBA8, colorSpace: sRGB)
        let rec709Image = CIImage(bitmapData: bytes, bytesPerRow: 4, size: CGSize(width: 1, height: 1), format: .RGBA8, colorSpace: rec709Gamma)

        let sRGBResult = try VideoColorPipeline.process(image: sRGBImage, sourceInfo: nil, settings: nil, lut: nil)
        let rec709Result = try VideoColorPipeline.process(image: rec709Image, sourceInfo: nil, settings: nil, lut: nil)
        let sRGBLinear = try readLinearRed(sRGBResult)
        let rec709Linear = try readLinearRed(rec709Result)
        XCTAssertEqual(sRGBLinear, 0.216, accuracy: 0.015)
        XCTAssertEqual(rec709Linear, 0.189, accuracy: 0.015)
        XCTAssertGreaterThan(abs(sRGBLinear - rec709Linear), 0.02)
    }

    func testHDRGreyRampRemainsOrderedTagged709AndKeepsAlpha() throws {
        let values: [Float] = [0, 0.25, 0.5, 0.625, 0.75, 0.875, 1]
        let colors = values.map { ($0, $0, $0, 1 as Float) }
        let source = try makeHalfBuffer(colors)
        let hlg = VideoColorInfo(
            colorPrimaries: kCVImageBufferColorPrimaries_ITU_R_2020 as String,
            transferFunction: kCVImageBufferTransferFunction_ITU_R_2100_HLG as String,
            yCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_2020 as String
        )
        let pq = VideoColorInfo(
            colorPrimaries: kCVImageBufferColorPrimaries_ITU_R_2020 as String,
            transferFunction: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String,
            yCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_2020 as String
        )

        for info in [hlg, pq] {
            let processed = try VideoColorPipeline.process(pixelBuffer: source, sourceInfo: info, settings: nil, lut: nil)
            let output = try render709Half(processed)
            let pixels = readHalfBuffer(output)
            let red = pixels.map { $0.0 }
            let profile = CGColorSpace(name: info.detectedInput == .hlg ? CGColorSpace.itur_2100_HLG : CGColorSpace.itur_2100_PQ)!
            let tagged = CIImage(cvPixelBuffer: source, options: [.colorSpace: profile])
            let taggedResult = try VideoColorPipeline.process(image: tagged, sourceInfo: info, settings: nil, lut: nil)
            let taggedPixels = readHalfBuffer(try render709Half(taggedResult))
            for (expected, actual) in zip(red, taggedPixels) {
                XCTAssertEqual(actual.0, expected, accuracy: 0.015)
            }
            let halfLUT = ClipLUT(lut: try CubeLUT(text: scaledCube(0.5), name: "Creative half"))
            let overridden = try VideoColorPipeline.process(
                pixelBuffer: source, sourceInfo: nil,
                settings: VideoColorSettings(input: try XCTUnwrap(info.detectedInput)), lut: halfLUT
            )
            let gradedPixels = readHalfBuffer(try render709Half(overridden))
            for (expected, actual) in zip(red, gradedPixels) {
                XCTAssertEqual(actual.0, expected * 0.5, accuracy: 0.015)
            }
            XCTAssertTrue(zip(red, red.dropFirst()).allSatisfy { $0.0 <= $0.1 })
            XCTAssertGreaterThan(red[4], red[3])
            XCTAssertGreaterThan(red[5], red[4])
            XCTAssertGreaterThan(red[5], 0.9)
            for pixel in pixels {
                XCTAssertEqual(pixel.0, pixel.1, accuracy: 0.012)
                XCTAssertEqual(pixel.1, pixel.2, accuracy: 0.012)
                XCTAssertEqual(pixel.3, 1, accuracy: 0.001)
            }
            XCTAssertEqual(CVBufferGetAttachment(output, kCVImageBufferColorPrimariesKey, nil)?.takeUnretainedValue() as? String,
                           kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
            XCTAssertEqual(CVBufferGetAttachment(output, kCVImageBufferTransferFunctionKey, nil)?.takeUnretainedValue() as? String,
                           kCVImageBufferTransferFunction_ITU_R_709_2 as String)
            XCTAssertEqual(CVBufferGetAttachment(output, kCVImageBufferYCbCrMatrixKey, nil)?.takeUnretainedValue() as? String,
                           kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String)
            XCTAssertNil(CVBufferGetAttachment(output, kCVImageBufferICCProfileKey, nil))
            XCTAssertNil(CVBufferGetAttachment(output, "LogTransferFunction" as CFString, nil))
        }

        let alphaInput = try makeHalfBuffer([(0.1, 0.1, 0.1, 0.5)])
        let alphaProcessed = try VideoColorPipeline.process(
            pixelBuffer: alphaInput,
            sourceInfo: hlg,
            settings: nil,
            lut: nil
        )
        let alphaOutput = try render709Half(alphaProcessed)
        XCTAssertEqual(readHalfBuffer(alphaOutput)[0].3, 0.5, accuracy: 0.002)
    }

    private func makeDescription(_ extensions: [String: Any]) throws -> CMFormatDescription {
        var description: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: 2,
            height: 2,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &description
        )
        guard status == noErr, let description else {
            throw NSError(domain: "VideoColorPipelineTests", code: Int(status))
        }
        return description
    }

    private func scaledCube(_ scale: Float) -> String {
        "LUT_3D_SIZE 2\n" + (0..<8).map { index in
            let rgb = [index & 1, (index >> 1) & 1, (index >> 2) & 1]
            return rgb.map { String(Float($0) * scale) }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    private func makeHalfBuffer(_ pixels: [(Float, Float, Float, Float)]) throws -> CVPixelBuffer {
        var candidate: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            pixels.count,
            1,
            kCVPixelFormatType_64RGBAHalf,
            nil,
            &candidate
        )
        guard status == kCVReturnSuccess, let buffer = candidate else {
            throw NSError(domain: "VideoColorPipelineTests", code: Int(status))
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else {
            throw NSError(domain: "VideoColorPipelineTests", code: 1)
        }
        let wordsPerRow = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<UInt16>.size
        let words = address.assumingMemoryBound(to: UInt16.self)
        for (index, pixel) in pixels.enumerated() {
            let values = [pixel.0, pixel.1, pixel.2, pixel.3].map { Float16($0).bitPattern }
            for channel in 0..<4 { words[index * 4 + channel] = values[channel] }
        }
        XCTAssertGreaterThanOrEqual(wordsPerRow, pixels.count * 4)
        return buffer
    }

    private func render709Half(_ image: CIImage) throws -> CVPixelBuffer {
        let width = Int(image.extent.width)
        var candidate: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            1,
            kCVPixelFormatType_64RGBAHalf,
            nil,
            &candidate
        )
        guard status == kCVReturnSuccess, let buffer = candidate else {
            throw NSError(domain: "VideoColorPipelineTests", code: Int(status))
        }
        VideoColorPipeline.makeContext().render(
            image,
            to: buffer,
            bounds: image.extent,
            colorSpace: VideoColorPipeline.outputColorSpace
        )
        // Poison the recycled-pool-style labels to ensure SDR output clears them.
        CVBufferSetAttachment(buffer, kCVImageBufferICCProfileKey, Data([1, 2, 3]) as CFData, .shouldPropagate)
        CVBufferSetAttachment(buffer, "LogTransferFunction" as CFString, "com.apple.rec2020.apple-log" as CFString, .shouldPropagate)
        VideoColorPipeline.markOutput(buffer)
        return buffer
    }

    private func readHalfBuffer(_ pixelBuffer: CVPixelBuffer) -> [(Float, Float, Float, Float)] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        let words = address.assumingMemoryBound(to: UInt16.self)
        return (0..<CVPixelBufferGetWidth(pixelBuffer)).map { index in
            (
                Float(Float16(bitPattern: words[index * 4])),
                Float(Float16(bitPattern: words[index * 4 + 1])),
                Float(Float16(bitPattern: words[index * 4 + 2])),
                Float(Float16(bitPattern: words[index * 4 + 3]))
            )
        }
    }

    private func readLinearRed(_ image: CIImage) throws -> Float {
        var candidate: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_64RGBAHalf, nil, &candidate)
        guard status == kCVReturnSuccess, let buffer = candidate else {
            throw NSError(domain: "VideoColorPipelineTests", code: Int(status))
        }
        let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        VideoColorPipeline.makeContext().render(image, to: buffer, bounds: image.extent, colorSpace: linear)
        return readHalfBuffer(buffer).first?.0 ?? .nan
    }
}
