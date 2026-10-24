#if canImport(AVFoundation)
import AVFoundation
import CoreImage
import CoreVideo
import Foundation

/// Converts source frames to the app's Rec.709 SDR working image and applies a clip LUT.
public enum VideoColorPipeline {
    public enum Failure: Error, LocalizedError {
        case unsupportedHDRSourceColorSpace
        case invalidColorTransform

        public var errorDescription: String? {
            switch self {
            case .unsupportedHDRSourceColorSpace:
                return "HDR input is missing color labels required to preserve its source color space."
            case .invalidColorTransform:
                return "Could not create the video color transform."
            }
        }
    }

    /// Rec.709 Scene profile synthesized from the same three tags written to video outputs.
    public static let outputColorSpace: CGColorSpace = {
        let attachments: [String: Any] = [
            kCVImageBufferColorPrimariesKey as String: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCVImageBufferTransferFunctionKey as String: kCVImageBufferTransferFunction_ITU_R_709_2,
            kCVImageBufferYCbCrMatrixKey as String: kCVImageBufferYCbCrMatrix_ITU_R_709_2
        ]
        if let colorSpace = CVImageBufferCreateColorSpaceFromAttachments(attachments as CFDictionary) {
            return colorSpace.takeRetainedValue()
        }
        return CGColorSpace(name: CGColorSpace.itur_709)!
    }()

    private static let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    public static let outputColorProperties: [String: String] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
    ]

    private static let shoulderKernel = CIColorKernel(source: """
    kernel vec4 rec709Shoulder(__sample pixel) {
        float alpha = pixel.a;
        if (!(alpha >= 0.0 && alpha <= 1.0)) {
            return vec4(0.0, 0.0, 0.0, 0.0);
        }
        if (alpha <= 0.0) { return vec4(0.0, 0.0, 0.0, 0.0); }
        vec3 rgb = pixel.rgb / alpha;
        if (!(rgb.r >= -1.0e20 && rgb.r <= 1.0e20
           && rgb.g >= -1.0e20 && rgb.g <= 1.0e20
           && rgb.b >= -1.0e20 && rgb.b <= 1.0e20)) {
            return vec4(0.0, 0.0, 0.0, alpha);
        }

        float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
        if (!(luminance >= -1.0e20 && luminance <= 1.0e20)) {
            return vec4(0.0, 0.0, 0.0, alpha);
        }
        float mapped = max(0.0, luminance);
        if (mapped > 0.75) {
            float over = mapped - 0.75;
            mapped = 0.75 + 0.25 * over / (over + 0.25);
        }
        vec3 scaled = luminance > 0.0 ? rgb * (mapped / luminance) : vec3(0.0);
        vec3 delta = scaled - vec3(mapped);
        float t = 1.0;
        if (delta.r > 0.0) { t = min(t, (1.0 - mapped) / delta.r); }
        else if (delta.r < 0.0) { t = min(t, (0.0 - mapped) / delta.r); }
        if (delta.g > 0.0) { t = min(t, (1.0 - mapped) / delta.g); }
        else if (delta.g < 0.0) { t = min(t, (0.0 - mapped) / delta.g); }
        if (delta.b > 0.0) { t = min(t, (1.0 - mapped) / delta.b); }
        else if (delta.b < 0.0) { t = min(t, (0.0 - mapped) / delta.b); }
        t = clamp(t, 0.0, 1.0);
        return vec4((vec3(mapped) + delta * t) * alpha, alpha);
    }
    """)

    // BT.2100 EOTFs, HLG's 1.2 display OOTF at 1000 nits, and the BT.2020→709 matrix.
    // The fixed 203-nit reference white follows BT.2408-6; this is the app's SDR mapping,
    // not an attempt to reproduce Resolve's HDR transform.
    private static let decodeHDRKernel = CIColorKernel(source: """
    kernel vec4 decodeHDR(__sample pixel, float pq) {
        float alpha = pixel.a;
        if (!(alpha >= 0.0 && alpha <= 1.0)) { return vec4(0.0); }
        if (alpha <= 0.0) { return vec4(0.0); }
        vec3 e = pixel.rgb / alpha;
        if (!(e.r >= -1.0e20 && e.r <= 1.0e20
           && e.g >= -1.0e20 && e.g <= 1.0e20
           && e.b >= -1.0e20 && e.b <= 1.0e20)) {
            return vec4(0.0, 0.0, 0.0, alpha);
        }
        e = clamp(e, vec3(0.0), vec3(1.0));
        vec3 linear;
        if (pq > 0.5) {
            vec3 p = pow(e, vec3(1.0 / 78.84375));
            vec3 denominator = max(vec3(18.8515625) - 18.6875 * p, vec3(0.000001));
            linear = pow(max(p - vec3(0.8359375), vec3(0.0)) / denominator,
                         vec3(1.0 / 0.1593017578125)) * (10000.0 / 203.0);
        } else {
            vec3 low = e * e / 3.0;
            vec3 high = (exp((e - vec3(0.55991073)) / 0.17883277) + vec3(0.28466892)) / 12.0;
            linear = mix(low, high, step(vec3(0.5), e));
            float luminance2020 = dot(linear, vec3(0.2627, 0.6780, 0.0593));
            linear *= pow(max(luminance2020, 0.0), 0.2) * (1000.0 / 203.0);
        }
        vec3 rgb709 = vec3(
            dot(linear, vec3(1.660491, -0.587641, -0.072850)),
            dot(linear, vec3(-0.124550, 1.132900, -0.008349)),
            dot(linear, vec3(-0.018151, -0.100579, 1.118730))
        );
        return vec4(rgb709 * alpha, alpha);
    }
    """)

    public static func makeContext() -> CIContext {
        CIContext(options: [
            .workingColorSpace: workingColorSpace,
            .outputColorSpace: outputColorSpace,
            .cacheIntermediates: true
        ])
    }

    /// Marks a rendered SDR buffer as Rec.709 and removes HDR signaling inherited from a pool.
    public static func markOutput(_ pixelBuffer: CVPixelBuffer) {
        CVBufferRemoveAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey)
        CVBufferRemoveAttachment(pixelBuffer, kCVImageBufferICCProfileKey)
        CVBufferRemoveAttachment(pixelBuffer, kCVImageBufferMasteringDisplayColorVolumeKey)
        CVBufferRemoveAttachment(pixelBuffer, kCVImageBufferContentLightLevelInfoKey)
        CVBufferRemoveAttachment(pixelBuffer, kCVImageBufferAmbientViewingEnvironmentKey)
        if #available(macOS 14.2, iOS 17.2, tvOS 17.2, *) {
            CVBufferRemoveAttachment(pixelBuffer, kCVImageBufferLogTransferFunctionKey)
        }
        CVBufferSetAttachment(
            pixelBuffer,
            kCVImageBufferColorPrimariesKey,
            kCVImageBufferColorPrimaries_ITU_R_709_2,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            pixelBuffer,
            kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_ITU_R_709_2,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            pixelBuffer,
            kCVImageBufferYCbCrMatrixKey,
            kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            .shouldPropagate
        )
    }

    public static func process(
        pixelBuffer: CVPixelBuffer,
        sourceInfo: VideoColorInfo?,
        settings: VideoColorSettings?,
        lut: ClipLUT?
    ) throws -> CIImage {
        try process(
            image: CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: NSNull()]),
            sourceInfo: sourceInfo,
            settings: settings,
            lut: lut
        )
    }

    public static func process(
        image inputImage: CIImage,
        sourceInfo: VideoColorInfo?,
        settings: VideoColorSettings?,
        lut: ClipLUT?
    ) throws -> CIImage {
        let embeddedColorSpace = inputImage.colorSpace
        let sourceImage: CIImage
        if let embeddedColorSpace {
            // Tagged CIImages already enter the working space automatically. Recover their
            // encoded samples before applying an input override or a source-conversion LUT.
            guard let encoded = inputImage.matchedFromWorkingSpace(to: embeddedColorSpace) else {
                throw Failure.invalidColorTransform
            }
            sourceImage = encoded
        } else {
            sourceImage = inputImage
        }
        let selectedInput = settings?.input ?? .automatic
        let input = selectedInput == .automatic ? (sourceInfo?.detectedInput ?? .automatic) : selectedInput
        let transfer = sourceInfo?.transferFunction
        let embeddedHDRInput = Self.hdrInput(embeddedColorSpace)
        let isHLG = selectedInput == .hlg || (selectedInput == .automatic
            && (transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String) || embeddedHDRInput == .hlg))
        let isPQ = selectedInput == .pq || (selectedInput == .automatic
            && (transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String) || embeddedHDRInput == .pq))
        let isLog = input == .log

        if let lut, lut.usage == .sourceConversion || isLog {
            let converted = try lut.applyingRaw(to: sourceImage)
            guard let output = converted.matchedToWorkingSpace(from: outputColorSpace) else {
                throw Failure.invalidColorTransform
            }
            return output
        }
        if isLog {
            throw CubeLUT.Failure.requiresSourceConversionLUT
        }

        var image: CIImage
        if isHLG || isPQ {
            if selectedInput == .automatic {
            let isBT2020 = sourceInfo?.colorPrimaries.map {
                $0 == (kCVImageBufferColorPrimaries_ITU_R_2020 as String)
            } ?? (embeddedHDRInput == (isHLG ? .hlg : .pq))
            guard isBT2020 else { throw Failure.unsupportedHDRSourceColorSpace }
            }
            guard let decodeHDRKernel,
                  let decoded = decodeHDRKernel.apply(
                    extent: sourceImage.extent,
                    arguments: [sourceImage, isPQ ? 1.0 : 0.0]
                  ),
                  let linear709 = decoded.matchedToWorkingSpace(from: workingColorSpace),
                  let shoulderKernel,
                  let mapped = shoulderKernel.apply(extent: linear709.extent, arguments: [linear709]) else {
                throw Failure.invalidColorTransform
            }
            image = mapped
        } else {
            let sourceColorSpace: CGColorSpace
            if selectedInput == .rec709 {
                sourceColorSpace = outputColorSpace
            } else if selectedInput == .sRGB {
                guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                    throw Failure.invalidColorTransform
                }
                sourceColorSpace = colorSpace
            } else if selectedInput == .automatic, let embeddedColorSpace {
                sourceColorSpace = embeddedColorSpace
            } else if selectedInput == .automatic, sourceInfo?.detectedInput == .rec709 {
                sourceColorSpace = outputColorSpace
            } else if selectedInput == .automatic, sourceInfo?.detectedInput == .sRGB {
                guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                    throw Failure.invalidColorTransform
                }
                sourceColorSpace = colorSpace
            } else if selectedInput == .automatic,
                      let sourceInfo,
                      let taggedColorSpace = Self.colorSpace(from: sourceInfo) {
                sourceColorSpace = taggedColorSpace
            } else {
                // Untagged or unsupported SDR is explicitly treated as Rec.709.
                sourceColorSpace = outputColorSpace
            }
            guard let normalized = sourceImage.matchedToWorkingSpace(from: sourceColorSpace) else {
                throw Failure.invalidColorTransform
            }
            image = normalized
        }

        if let lut {
            guard let encoded709 = image.matchedFromWorkingSpace(to: outputColorSpace) else {
                throw Failure.invalidColorTransform
            }
            let graded = try lut.applyingRaw(to: encoded709)
            guard let normalized709 = graded.matchedToWorkingSpace(from: outputColorSpace) else {
                throw Failure.invalidColorTransform
            }
            image = normalized709
        }
        return image
    }

    private static func colorSpace(from info: VideoColorInfo) -> CGColorSpace? {
        guard let primaries = info.colorPrimaries,
              let transfer = info.transferFunction,
              let matrix = info.yCbCrMatrix else { return nil }
        let attachments: [String: Any] = [
            kCVImageBufferColorPrimariesKey as String: primaries,
            kCVImageBufferTransferFunctionKey as String: transfer,
            kCVImageBufferYCbCrMatrixKey as String: matrix
        ]
        return CVImageBufferCreateColorSpaceFromAttachments(attachments as CFDictionary)?.takeRetainedValue()
    }

    private static func hdrInput(_ colorSpace: CGColorSpace?) -> VideoColorInput? {
        guard let colorSpace else { return nil }
        if let pq = CGColorSpace(name: CGColorSpace.itur_2100_PQ), CFEqual(colorSpace, pq) { return .pq }
        if let hlg = CGColorSpace(name: CGColorSpace.itur_2100_HLG), CFEqual(colorSpace, hlg) { return .hlg }
        return nil
    }
}

#endif
