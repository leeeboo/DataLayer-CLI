import AVFoundation
import CoreImage

/// Carries per-clip color interpretation and optional LUTs through video composition.
final class LUTVideoInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    var requiredSourceTrackIDs: [NSValue]? { trackID.map { [NSNumber(value: $0)] } ?? [] }
    let trackID: CMPersistentTrackID?
    let transform: CGAffineTransform
    let sourceInfo: VideoColorInfo?
    let colorSettings: VideoColorSettings?
    let lut: ClipLUT?

    init(
        timeRange: CMTimeRange,
        trackID: CMPersistentTrackID?,
        transform: CGAffineTransform,
        sourceInfo: VideoColorInfo?,
        colorSettings: VideoColorSettings?,
        lut: ClipLUT?
    ) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.transform = transform
        self.sourceInfo = sourceInfo
        self.colorSettings = colorSettings
        self.lut = lut
    }
}

final class LUTVideoCompositor: NSObject, AVVideoCompositing {
    private let context = VideoColorPipeline.makeContext()
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf,
         kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()]
    }
    var supportsWideColorSourceFrames: Bool { true }
    var supportsHDRSourceFrames: Bool { true }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            do {
                guard let instruction = request.videoCompositionInstruction as? LUTVideoInstruction,
                      let buffer = request.renderContext.newPixelBuffer() else {
                    throw CubeLUT.Failure.invalidCube
                }
                let bounds = CGRect(origin: .zero, size: request.renderContext.size)
                let background = CIImage(color: .black).cropped(to: bounds)
                var image = background
                if let trackID = instruction.trackID {
                    guard let source = request.sourceFrame(byTrackID: trackID) else {
                        throw OverlayVideoError.unreadableVideo("Missing LUT preview source frame.")
                    }
                    image = try VideoColorPipeline.process(
                        pixelBuffer: source,
                        sourceInfo: instruction.sourceInfo,
                        settings: instruction.colorSettings,
                        lut: instruction.lut
                    )
                        .transformed(by: instruction.transform)
                        .composited(over: background)
                }
                context.render(image, to: buffer, bounds: bounds, colorSpace: VideoColorPipeline.outputColorSpace)
                VideoColorPipeline.markOutput(buffer)
                request.finish(withComposedVideoFrame: buffer)
            } catch { request.finish(with: error) }
        }
    }
}
