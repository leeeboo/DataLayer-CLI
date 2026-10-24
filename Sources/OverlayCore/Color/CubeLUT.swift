#if canImport(CoreImage)
import CoreImage
#endif
import Foundation

/// A validated 3D .cube LUT. Embedded in clips so projects never depend on the local library.
/// ponytail: Per-clip snapshots duplicate tables in JSON; deduplicate at project level if large timelines need it.
public struct CubeLUT: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let dimension: Int
    public let cubeData: Data

    public enum Failure: Error { case invalidCube, unsupportedCube, invalidIntensity, requiresSourceConversionLUT }
    public static let maximumFileSize = 64 * 1_024 * 1_024

    public init(text: String, name: String) throws {
        guard text.utf8.count <= Self.maximumFileSize else { throw Failure.invalidCube }
        var dimension: Int?
        var values = [Float]()
        var headers = Set<String>()
        let content = text.hasPrefix("\u{FEFF}") ? text.dropFirst() : text[...]
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let words = line.split(whereSeparator: \.isWhitespace)
            guard let first = words.first else { continue }
            if Float(first) != nil {
                guard let size = dimension, words.count == 3, values.count < size * size * size * 4 else {
                    throw Failure.invalidCube
                }
                let rgb = try words.map { word -> Float in
                    guard let value = Float(word), value.isFinite else { throw Failure.invalidCube }
                    return value
                }
                values.append(contentsOf: rgb)
                values.append(1)
            } else {
                guard values.isEmpty, headers.insert(String(first)).inserted else { throw Failure.invalidCube }
                switch first {
                case "TITLE": break // The file name is the initial, editable library name.
                case "LUT_3D_SIZE":
                    guard words.count == 2, let size = Int(words[1]), (2...65).contains(size) else {
                        throw Failure.unsupportedCube
                    }
                    dimension = size
                    values.reserveCapacity(size * size * size * 4)
                case "DOMAIN_MIN":
                    guard words.count == 4, words.dropFirst().allSatisfy({ Float($0) == 0 }) else {
                        throw Failure.unsupportedCube
                    }
                case "DOMAIN_MAX":
                    guard words.count == 4, words.dropFirst().allSatisfy({ Float($0) == 1 }) else {
                        throw Failure.unsupportedCube
                    }
                case "LUT_3D_INPUT_RANGE":
                    guard words.count == 3, Float(words[1]) == 0, Float(words[2]) == 1 else {
                        throw Failure.unsupportedCube
                    }
                default: throw Failure.unsupportedCube
                }
            }
        }
        guard let size = dimension, values.count == size * size * size * 4 else { throw Failure.invalidCube }
        self.id = UUID()
        self.name = name
        self.dimension = size
        self.cubeData = values.withUnsafeBytes { Data($0) }
    }

    private enum CodingKeys: String, CodingKey { case id, name, dimension, cubeData }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        dimension = try container.decode(Int.self, forKey: .dimension)
        guard (2...65).contains(dimension) else { throw Failure.invalidCube }
        cubeData = try container.decode(Data.self, forKey: .cubeData)
        guard cubeData.count == dimension * dimension * dimension * 4 * MemoryLayout<Float>.size else {
            throw Failure.invalidCube
        }
        let valid = cubeData.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 4).allSatisfy { offset in
                let value = bytes.loadUnaligned(fromByteOffset: offset, as: Float.self)
                return value.isFinite && (offset % 16 != 12 || value == 1)
            }
        }
        guard valid else { throw Failure.invalidCube }
    }
}

public enum VideoLUTUsage: String, Codable, Sendable {
    case creative
    case sourceConversion
}

public struct ClipLUT: Codable, Equatable, Sendable {
    public var lut: CubeLUT
    public private(set) var intensity: Double
    public var usage: VideoLUTUsage

    public init(lut: CubeLUT, intensity: Double = 1, usage: VideoLUTUsage = .creative) {
        self.lut = lut
        self.usage = usage
        self.intensity = !intensity.isFinite ? 1 : min(1, max(0, intensity))
    }

    private enum CodingKeys: String, CodingKey { case lut, intensity, usage }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lut = try container.decode(CubeLUT.self, forKey: .lut)
        usage = try container.decodeIfPresent(VideoLUTUsage.self, forKey: .usage) ?? .creative
        let decodedIntensity = try container.decode(Double.self, forKey: .intensity)
        guard decodedIntensity.isFinite, (0...1).contains(decodedIntensity) else {
            throw CubeLUT.Failure.invalidIntensity
        }
        intensity = decodedIntensity
    }

    #if canImport(CoreImage)
    public func applying(to image: CIImage) throws -> CIImage {
        guard intensity > 0 else { return image }
        // .cube tables use display-referred RGB; explicitly use sRGB, not CI's linear default.
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace", parameters: [
            "inputImage": image,
            "inputCubeDimension": lut.dimension,
            "inputCubeData": lut.cubeData,
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!
        ]), let graded = filter.outputImage else { throw CubeLUT.Failure.invalidCube }
        // Preserve source alpha: a cube with opaque entries otherwise colors transparent borders.
        let masked = graded.applyingFilter("CIBlendWithAlphaMask", parameters: [
            "inputBackgroundImage": CIImage.empty(), "inputMaskImage": image
        ]).cropped(to: image.extent)
        if intensity == 1 { return masked }
        return image.applyingFilter("CIDissolveTransition", parameters: [
            "inputTargetImage": masked, "inputTime": intensity
        ]).cropped(to: image.extent)
    }

    func applyingRaw(to image: CIImage) throws -> CIImage {
        guard intensity > 0 else { return image }
        guard let filter = CIFilter(name: "CIColorCube", parameters: [
            "inputImage": image,
            "inputCubeDimension": lut.dimension,
            "inputCubeData": lut.cubeData
        ]), let graded = filter.outputImage else { throw CubeLUT.Failure.invalidCube }
        let masked = graded.applyingFilter("CIBlendWithAlphaMask", parameters: [
            "inputBackgroundImage": CIImage.empty(), "inputMaskImage": image
        ]).cropped(to: image.extent)
        if intensity == 1 { return masked }
        return image.applyingFilter("CIDissolveTransition", parameters: [
            "inputTargetImage": masked, "inputTime": intensity
        ]).cropped(to: image.extent)
    }

    public func applying(to image: CGImage, context: CIContext) throws -> CGImage {
        let result = try applying(to: CIImage(cgImage: image))
        guard let output = context.createCGImage(result, from: result.extent) else { throw CubeLUT.Failure.invalidCube }
        return output
    }
    #endif
}
