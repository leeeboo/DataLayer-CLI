#if canImport(CoreMedia)
import CoreMedia
import CoreVideo
#endif
import Foundation

public enum VideoColorInput: String, Codable, CaseIterable, Sendable {
    case automatic
    case rec709
    case sRGB
    case hlg
    case pq
    case log
}

public struct VideoColorSettings: Codable, Equatable, Sendable {
    public var input: VideoColorInput

    public init(input: VideoColorInput = .automatic) {
        self.input = input
    }
}

/// Color labels copied from the source format description without filling missing values.
public struct VideoColorInfo: Codable, Equatable, Sendable {
    public var colorPrimaries: String?
    public var transferFunction: String?
    public var yCbCrMatrix: String?
    public var isFullRange: Bool?
    public var logTransferFunction: String?

    public init(
        colorPrimaries: String? = nil,
        transferFunction: String? = nil,
        yCbCrMatrix: String? = nil,
        isFullRange: Bool? = nil,
        logTransferFunction: String? = nil
    ) {
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.yCbCrMatrix = yCbCrMatrix
        self.isFullRange = isFullRange
        self.logTransferFunction = logTransferFunction
    }

    public var detectedInput: VideoColorInput? {
        if logTransferFunction == "com.apple.rec2020.apple-log"
            || logTransferFunction == "com.apple.apple-wide-gamut.apple-log" { return .log }

        #if canImport(CoreVideo)
        switch (colorPrimaries, transferFunction) {
        case let (primaries?, transfer?) where primaries == (kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
            && transfer == (kCVImageBufferTransferFunction_ITU_R_709_2 as String):
            return .rec709
        case let (primaries?, transfer?) where primaries == (kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
            && transfer == (kCVImageBufferTransferFunction_sRGB as String):
            return .sRGB
        case let (primaries?, transfer?) where primaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String)
            && transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String):
            return .hlg
        case let (primaries?, transfer?) where primaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String)
            && transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String):
            return .pq
        default:
            return nil
        }
        #else
        switch transferFunction?.lowercased() {
        case "bt709", "itu_r_709_2": return .rec709
        case "iec61966-2-1", "srgb": return .sRGB
        case "arib-std-b67", "itu_r_2100_hlg": return .hlg
        case "smpte2084", "smpte_st_2084_pq": return .pq
        default: return nil
        }
        #endif
    }

    /// True when the source labels do not identify one of the supported input profiles.
    public var isAssumed: Bool { detectedInput == nil }

    #if canImport(CoreMedia)
    public static func read(from formatDescription: CMFormatDescription) -> VideoColorInfo? {
        guard let rawExtensions = CMFormatDescriptionGetExtensions(formatDescription) else { return nil }
        let extensions = rawExtensions as NSDictionary
        func string(_ key: CFString) -> String? { extensions.object(forKey: key) as? String }
        func bool(_ key: CFString) -> Bool? { extensions.object(forKey: key) as? Bool }

        // Raw extension names keep Apple Log detection available on macOS 13, before CoreMedia added constants.
        let logFunction = string("LogTransferFunction" as CFString)
        let info = VideoColorInfo(
            colorPrimaries: string(kCMFormatDescriptionExtension_ColorPrimaries),
            transferFunction: string(kCMFormatDescriptionExtension_TransferFunction),
            yCbCrMatrix: string(kCMFormatDescriptionExtension_YCbCrMatrix),
            isFullRange: bool(kCMFormatDescriptionExtension_FullRangeVideo),
            logTransferFunction: logFunction
        )
        return info.colorPrimaries == nil && info.transferFunction == nil && info.yCbCrMatrix == nil
            && info.isFullRange == nil && info.logTransferFunction == nil ? nil : info
    }
    #endif
}
