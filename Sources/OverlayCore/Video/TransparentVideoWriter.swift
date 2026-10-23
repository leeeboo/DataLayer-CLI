import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import VideoToolbox

public enum OverlayExportMode: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case overlay
    case video

    public var id: String { rawValue }

    public var defaultCodec: OverlayVideoCodec {
        switch self {
        case .overlay:
            return .hevcAlpha
        case .video:
            return .hevc
        }
    }
}

public enum OverlayVideoCodec: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case hevcAlpha = "hevc-alpha"
    case proRes4444 = "prores-4444"
    case hevc = "hevc"
    case h264 = "h264"

    public var id: String { rawValue }

    var avCodecType: AVVideoCodecType {
        switch self {
        case .hevcAlpha:
            return .hevcWithAlpha
        case .proRes4444:
            return .proRes4444
        case .hevc:
            return .hevc
        case .h264:
            return .h264
        }
    }

    public var exportMode: OverlayExportMode {
        switch self {
        case .hevcAlpha, .proRes4444:
            return .overlay
        case .hevc, .h264:
            return .video
        }
    }

    public var displayName: String {
        switch self {
        case .hevcAlpha:
            return "HEVC/H.265 with alpha"
        case .proRes4444:
            return "Apple ProRes 4444"
        case .hevc:
            return "HEVC/H.265"
        case .h264:
            return "H.264"
        }
    }
}

public struct TransparentVideoWriterConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case width, height, framesPerSecond, startTime, duration, averageBitRate, timeSync
        case activityOffsetMilliseconds, fitClockOffsetMilliseconds, codec, overlayLayout, distanceUnit, activityTrim
        case timeZone
    }
    public var width: Int
    public var height: Int
    public var framesPerSecond: Double
    public var startTime: TimeInterval
    public var duration: TimeInterval
    public var averageBitRate: Int
    public var timeSync: TelemetryTimeSync
    public var activityOffsetMilliseconds: Int {
        didSet {
            activityOffsetMilliseconds = OverlayRenderConfig.clampedActivityOffsetMilliseconds(activityOffsetMilliseconds)
        }
    }
    public var fitClockOffsetMilliseconds: Int {
        didSet {
            fitClockOffsetMilliseconds = OverlayRenderConfig.clampedFitClockOffsetMilliseconds(fitClockOffsetMilliseconds)
        }
    }
    public var codec: OverlayVideoCodec
    public var overlayLayout: OverlayLayout
    public var distanceUnit: OverlayDistanceUnit
    public var timeZone: TimeZone?
    public var activityTrim: ActivityTrim
    public var progressHandler: ((Int, Int) -> Void)?
    public var cancellationHandler: (() -> Bool)?
    public var diagnosticsHandler: ((VideoExportDiagnosticEvent) -> Void)?
    /// Runtime-only scratch location; never persisted in projects or transferred over IPC.
    public var temporaryDirectory: URL? = nil

    public init(
        width: Int,
        height: Int,
        framesPerSecond: Double,
        startTime: TimeInterval = 0,
        duration: TimeInterval,
        averageBitRate: Int = 12_000_000,
        timeSync: TelemetryTimeSync = .identity,
        activityOffsetMilliseconds: Int? = nil,
        fitClockOffsetMilliseconds: Int? = nil,
        codec: OverlayVideoCodec = .hevcAlpha,
        overlayLayout: OverlayLayout = .default,
        distanceUnit: OverlayDistanceUnit = .kilometers,
        timeZone: TimeZone? = nil,
        activityTrim: ActivityTrim = .none,
        progressHandler: ((Int, Int) -> Void)? = nil,
        cancellationHandler: (() -> Bool)? = nil,
        diagnosticsHandler: ((VideoExportDiagnosticEvent) -> Void)? = nil,
        temporaryDirectory: URL? = nil
    ) {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.startTime = startTime
        self.duration = duration
        self.averageBitRate = averageBitRate
        self.timeSync = timeSync
        self.activityOffsetMilliseconds = OverlayRenderConfig.clampedActivityOffsetMilliseconds(activityOffsetMilliseconds)
        self.fitClockOffsetMilliseconds = OverlayRenderConfig.clampedFitClockOffsetMilliseconds(fitClockOffsetMilliseconds)
        self.codec = codec
        self.overlayLayout = overlayLayout
        self.distanceUnit = distanceUnit
        self.timeZone = timeZone
        self.activityTrim = activityTrim
        self.progressHandler = progressHandler
        self.cancellationHandler = cancellationHandler
        self.diagnosticsHandler = diagnosticsHandler
        self.temporaryDirectory = temporaryDirectory
    }
}

public struct TransparentVideoFrameTiming {
    public static let preferredTimescale: CMTimeScale = 600_000

    public let framesPerSecond: Double
    public let duration: TimeInterval
    public let frameDuration: CMTime
    public let frameCount: Int
    public let frameCountWasClamped: Bool
    private let usesExactFrameDuration: Bool
    public var mediaTimeScale: CMTimeScale { frameDuration.timescale }
    public var outputDuration: CMTime { presentationTime(for: frameCount) }

    public init(framesPerSecond: Double, duration: TimeInterval) {
        let fps = framesPerSecond.isFinite ? framesPerSecond : 1
        let duration = duration.isFinite ? duration : 0
        self.framesPerSecond = max(1, Self.canonicalFramesPerSecond(fps))
        self.duration = max(0, duration)
        if let exactFrameDuration = Self.exactFrameDuration(framesPerSecond: self.framesPerSecond) {
            self.frameDuration = exactFrameDuration
            self.usesExactFrameDuration = true
        } else {
            self.frameDuration = CMTime(
                seconds: 1.0 / self.framesPerSecond,
                preferredTimescale: Self.preferredTimescale
            )
            self.usesExactFrameDuration = false
        }

        let rawFrameCount = ceil(self.duration * self.framesPerSecond - 0.000_000_1)
        if rawFrameCount.isFinite, rawFrameCount < Double(Int.max) {
            self.frameCount = max(1, Int(rawFrameCount))
            self.frameCountWasClamped = false
        } else if self.duration <= 0 {
            self.frameCount = 1
            self.frameCountWasClamped = false
        } else {
            self.frameCount = Int.max
            self.frameCountWasClamped = true
        }
    }

    public func presentationTime(for frameIndex: Int) -> CMTime {
        let safeFrameIndex = max(0, frameIndex)
        guard usesExactFrameDuration else {
            return CMTime(
                seconds: Double(safeFrameIndex) / framesPerSecond,
                preferredTimescale: Self.preferredTimescale
            )
        }
        let multiplied = CMTimeValue(safeFrameIndex).multipliedReportingOverflow(by: frameDuration.value)
        if multiplied.overflow {
            return CMTime(
                seconds: Double(safeFrameIndex) * CMTimeGetSeconds(frameDuration),
                preferredTimescale: frameDuration.timescale
            )
        }
        return CMTime(value: multiplied.partialValue, timescale: frameDuration.timescale)
    }

    private static func exactFrameDuration(framesPerSecond: Double) -> CMTime? {
        if let exact = FrameRateCanonicalizer.exactFrameDuration(for: framesPerSecond) {
            return exact
        }
        let ntsc11988 = 120_000.0 / 1_001.0
        guard abs(framesPerSecond - ntsc11988) < 0.000_001 else { return nil }
        return CMTime(value: 1_001, timescale: 120_000)
    }

    private static func canonicalFramesPerSecond(_ framesPerSecond: Double) -> Double {
        let canonical = FrameRateCanonicalizer.canonicalize(framesPerSecond)
        let ntsc11988 = 120_000.0 / 1_001.0
        if abs(framesPerSecond - 119.88) < 0.001 || abs(framesPerSecond - ntsc11988) < 0.000_001 {
            return ntsc11988
        }
        return canonical
    }
}

public final class TransparentVideoWriter {
    private static let temporaryFilePrefix = "DataLayerStudio-"

    private let outputURL: URL
    private let series: TelemetrySeries
    private let config: TransparentVideoWriterConfig
    private let diagnosticDeliveryLock = NSLock()
    private var didReportPreciseFailure = false

    public init(outputURL: URL, series: TelemetrySeries, config: TransparentVideoWriterConfig) {
        self.outputURL = outputURL
        self.series = series
        self.config = config
    }

    public func write() throws {
        try VideoExportCleanup.check()
        #if os(macOS)
        if let executable = VideoExportWorker.executableURL {
            try VideoExportWorker.writeOverlay(outputURL: outputURL, series: series, config: config,
                                               executableURL: executable)
            return
        }
        try VideoExportSupport.performWriting(
            cancellationHandler: config.cancellationHandler,
            progressHandler: config.progressHandler,
            diagnosticsHandler: config.diagnosticsHandler,
            securityScopedURLs: [outputURL]
        ) { control in
            var config = self.config
            config.cancellationHandler = { control.isCancelled }
            config.progressHandler = control.recordProgress
            config.diagnosticsHandler = control.recordDiagnostic
            try TransparentVideoWriter(outputURL: self.outputURL, series: self.series, config: config).writeUnmonitored()
        }
        #else
        try writeUnmonitored()
        #endif
    }

    func writeUnmonitored() throws {
        resetDiagnosticFailure()
        if config.cancellationHandler?() == true {
            let error = OverlayVideoError.cancelled
            diagnoseFailure(stage: .prepareWriter, error: error)
            throw error
        }

        Self.removeStaleTemporaryOutputs()
        let temporaryOutputURL = makeTemporaryOutputURL()
        removePartialOutput(at: temporaryOutputURL)

        do {
            try write(to: temporaryOutputURL)
            diagnose(stage: .installOutput, phase: .begin)
            do {
                try VideoExportSupport.installCompletedOutput(
                    from: temporaryOutputURL,
                    to: outputURL,
                    cancellationHandler: config.cancellationHandler,
                    diagnosticsHandler: config.diagnosticsHandler == nil ? nil : deliverDiagnostic
                )
            } catch {
                if !hasReportedPreciseFailure { diagnoseFailure(stage: .installOutput, error: error) }
                throw error
            }
            diagnose(stage: .installOutput, phase: .end)
            diagnose(stage: .exportCompleted, phase: .end)
        } catch {
            removePartialOutput(at: temporaryOutputURL)
            throw error
        }
    }

    public static func removeStaleTemporaryOutputs() {
        removeStaleTemporaryOutputs(in: FileManager.default.temporaryDirectory)
    }

    public static func removeStaleTemporaryOutputs(in directory: URL) {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in urls where shouldRemoveTemporaryOutput(url) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func write(to temporaryOutputURL: URL) throws {
        do {
            try validateConfiguration()
        } catch {
            diagnoseFailure(stage: .prepareWriter, error: error)
            throw error
        }

        let width = config.width
        let height = config.height
        let timing = TransparentVideoFrameTiming(
            framesPerSecond: config.framesPerSecond,
            duration: config.duration
        )
        let fps = timing.framesPerSecond
        let frameCount = timing.frameCount
        diagnose(stage: .prepareWriter, phase: .begin, totalFrames: frameCount)
        guard !timing.frameCountWasClamped else {
            let error = OverlayVideoError.invalidConfiguration(
                "Output duration and frame rate produce too many frames. Lower the duration or frame rate."
            )
            diagnoseFailure(stage: .prepareWriter, error: error, totalFrames: frameCount)
            throw error
        }
        let encoderFrameRate: Int
        do {
            encoderFrameRate = try encoderFrameRateValue(fps)
        } catch {
            diagnoseFailure(stage: .prepareWriter, error: error, totalFrames: frameCount)
            throw error
        }

        let hardwareProfile = OverlayHardwareProfile.current
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: temporaryOutputURL, fileType: .mov)
        } catch {
            diagnoseFailure(stage: .prepareWriter, error: error, totalFrames: frameCount)
            throw error
        }
        writer.movieTimeScale = timing.mediaTimeScale
        let settings = Self.videoOutputSettings(
            width: width,
            height: height,
            codec: config.codec,
            averageBitRate: config.averageBitRate,
            encoderFrameRate: encoderFrameRate,
            expectedSourceFrameRate: fps,
            hardwareProfile: hardwareProfile
        )

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.mediaTimeScale = timing.mediaTimeScale
        input.expectsMediaDataInRealTime = false
        input.performsMultiPassEncodingIfSupported = false
        do {
            guard writer.canAdd(input) else {
                throw OverlayVideoError.unsupportedEncoder(
                    "This macOS installation cannot add a \(config.codec.displayName) video writer input."
                )
            }
            writer.add(input)
        } catch {
            diagnoseFailure(stage: .prepareWriter, error: error, totalFrames: frameCount, writer: writer)
            throw error
        }

        let sourceAttributes = OverlayPixelBufferAttributes.canvas(width: width, height: height)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourceAttributes
        )

        do {
            guard writer.startWriting() else {
                throw OverlayVideoError.cannotStartWriter(
                    describe(error: writer.error, codec: config.codec),
                    underlying: writer.error
                )
            }
            writer.startSession(atSourceTime: .zero)
        } catch {
            diagnoseFailure(stage: .prepareWriter, error: error, totalFrames: frameCount, writer: writer)
            throw error
        }
        diagnose(stage: .prepareWriter, phase: .end, totalFrames: frameCount, writer: writer)

        let renderer = OverlayRenderer(
            series: series,
            config: OverlayRenderConfig(
                size: CGSize(width: width, height: height),
                timeSync: config.timeSync,
                activityOffsetMilliseconds: config.activityOffsetMilliseconds,
                fitClockOffsetMilliseconds: config.fitClockOffsetMilliseconds,
                layout: config.overlayLayout,
                distanceUnit: config.distanceUnit,
                timeZone: config.timeZone ?? .current,
                activityTrim: config.activityTrim
            )
        )

        let renderQueue = DispatchQueue(label: "run.libo.overlay.video-writer")
        let renderFinished = DispatchSemaphore(value: 0)
        let codec = config.codec
        let alphaContext = codec == .hevcAlpha ? OverlayCIContextFactory.makeContext(profile: hardwareProfile) : nil
        let alphaColorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaRenderPool: CVPixelBufferPool?
        do {
            alphaRenderPool = codec == .hevcAlpha
                ? try Self.makePixelBufferPool(width: width, height: height, minimumBufferCount: 2)
                : nil
        } catch {
            diagnoseFailure(stage: .prepareWriter, error: error, totalFrames: frameCount, writer: writer)
            throw error
        }
        let progressHandler = config.progressHandler
        let cancellationHandler = config.cancellationHandler
        let exportStartTime = config.startTime
        var frameIndex = 0
        var renderError: Error?
        var didFinishInput = false
        let renderDiagnosticTracker = config.diagnosticsHandler.map { _ in TransparentRenderDiagnosticStageTracker() }
        let reportLatestRenderDiagnostic: () -> Void = {
            guard let renderDiagnosticTracker else { return }
            self.deliverLatestRenderDiagnostic(from: renderDiagnosticTracker)
        }

        diagnose(stage: .awaitReady, phase: .begin, totalFrames: frameCount, writer: writer)
        input.requestMediaDataWhenReady(on: renderQueue) {
            renderDiagnosticTracker?.update(self.diagnosticEvent(
                stage: .awaitReady,
                phase: .update,
                frameIndex: frameIndex,
                totalFrames: frameCount,
                writer: writer,
                inputReady: input.isReadyForMoreMediaData
            ))
            while input.isReadyForMoreMediaData, frameIndex < frameCount, renderError == nil {
                var activeStage: VideoExportDiagnosticEvent.Stage = .renderOverlay
                do {
                    try autoreleasepool {
                        if cancellationHandler?() == true {
                            throw OverlayVideoError.cancelled
                        }

                        guard let pool = adaptor.pixelBufferPool else {
                            throw OverlayVideoError.cannotCreatePixelBuffer
                        }
                        let appendBuffer = try Self.makePixelBuffer(from: pool)
                        let renderBuffer: CVPixelBuffer
                        if let alphaRenderPool {
                            renderBuffer = try Self.makePixelBuffer(from: alphaRenderPool)
                        } else {
                            renderBuffer = appendBuffer
                        }

                        let presentationTime = timing.presentationTime(for: frameIndex)
                        let videoTime = exportStartTime + CMTimeGetSeconds(presentationTime)
                        renderDiagnosticTracker?.update(self.diagnosticEvent(
                            stage: .renderOverlay,
                            phase: .begin,
                            frameIndex: frameIndex,
                            totalFrames: frameCount,
                            writer: writer
                        ))
                        try renderer.render(videoTime: videoTime, into: renderBuffer)
                        if let alphaContext {
                            activeStage = .ciComposite
                            renderDiagnosticTracker?.update(self.diagnosticEvent(
                                stage: .ciComposite,
                                phase: .begin,
                                frameIndex: frameIndex,
                                totalFrames: frameCount,
                                writer: writer
                            ))
                            Self.prepareHEVCAlphaForEncoding(
                                from: renderBuffer,
                                to: appendBuffer,
                                context: alphaContext,
                                colorSpace: alphaColorSpace
                            )
                        } else {
                            Self.preparePremultipliedAlphaForEncoding(on: appendBuffer)
                        }
                        activeStage = .appendFrame
                        renderDiagnosticTracker?.update(self.diagnosticEvent(
                            stage: .appendFrame,
                            phase: .begin,
                            frameIndex: frameIndex,
                            totalFrames: frameCount,
                            writer: writer,
                            inputReady: input.isReadyForMoreMediaData
                        ))
                        guard try Self.appendPixelBuffer(
                            appendBuffer,
                            to: input,
                            at: presentationTime,
                            duration: timing.frameDuration
                        ) else {
                            throw OverlayVideoError.writerFailed(
                                self.describe(error: writer.error, codec: codec),
                                underlying: writer.error
                            )
                        }

                        frameIndex += 1
                        if frameIndex == frameCount || frameIndex % Int(max(1, fps)) == 0 {
                            progressHandler?(frameIndex, frameCount)
                        }
                    }
                } catch {
                    self.diagnoseFailure(
                        stage: activeStage,
                        error: error,
                        frameIndex: frameIndex,
                        totalFrames: frameCount,
                        writer: writer,
                        inputReady: input.isReadyForMoreMediaData
                    )
                    renderError = error
                }
            }

            if frameIndex < frameCount, renderError == nil {
                renderDiagnosticTracker?.update(self.diagnosticEvent(
                    stage: .awaitReady,
                    phase: .update,
                    frameIndex: frameIndex,
                    totalFrames: frameCount,
                    writer: writer,
                    inputReady: input.isReadyForMoreMediaData
                ))
            }
            if (frameIndex >= frameCount || renderError != nil), !didFinishInput {
                didFinishInput = true
                self.deliverLatestRenderDiagnostic(from: renderDiagnosticTracker)
                self.diagnose(stage: .finishInput, phase: .begin, frameIndex: frameIndex, totalFrames: frameCount, writer: writer)
                if renderError == nil {
                    writer.endSession(atSourceTime: timing.outputDuration)
                }
                input.markAsFinished()
                self.diagnose(stage: .finishInput, phase: .end, frameIndex: frameIndex, totalFrames: frameCount, writer: writer)
                renderFinished.signal()
            }
        }
        VideoExportSupport.waitForRenderCompletion(
            renderFinished,
            cancellationHandler: cancellationHandler,
            heartbeatHandler: reportLatestRenderDiagnostic,
            cancelProducer: {
                renderQueue.async {
                    guard !didFinishInput else { return }
                    renderError = OverlayVideoError.cancelled
                    didFinishInput = true
                    input.markAsFinished()
                    renderFinished.signal()
                }
            }
        )
        diagnose(stage: .awaitReady, phase: .end, frameIndex: frameIndex, totalFrames: frameCount, writer: writer)

        if let renderError {
            writer.cancelWriting()
            if !hasReportedPreciseFailure {
                diagnoseFailure(
                    stage: .awaitReady,
                    error: renderError,
                    frameIndex: frameIndex,
                    totalFrames: frameCount,
                    writer: writer
                )
            }
            throw renderError
        }

        diagnose(stage: .finishWriter, phase: .begin, writer: writer)
        do {
            try VideoExportSupport.finishWriting(
                writer,
                cancellationHandler: cancellationHandler
            )
        } catch {
            diagnoseFailure(stage: .finishWriter, error: error, writer: writer)
            throw error
        }
        diagnose(stage: .finishWriter, phase: .end, writer: writer)

        guard writer.status == .completed else {
            let error = OverlayVideoError.writerFailed(
                describe(error: writer.error, codec: config.codec),
                underlying: writer.error
            )
            diagnoseFailure(stage: .finishWriter, error: error, writer: writer)
            throw error
        }
    }

    private func validateConfiguration() throws {
        guard config.width > 0, config.height > 0 else {
            throw OverlayVideoError.invalidConfiguration("Output width and height must be positive.")
        }
        guard config.width <= 16_384, config.height <= 16_384 else {
            throw OverlayVideoError.invalidConfiguration("Output width and height must be 16,384 px or smaller.")
        }
        guard config.width % 2 == 0, config.height % 2 == 0 else {
            throw OverlayVideoError.invalidConfiguration("Output width and height must be even pixel values.")
        }
        guard config.framesPerSecond.isFinite, config.framesPerSecond > 0 else {
            throw OverlayVideoError.invalidConfiguration("Output frame rate must be a positive finite number.")
        }
        guard config.startTime.isFinite, config.startTime >= 0 else {
            throw OverlayVideoError.invalidConfiguration("Output start time must be a non-negative finite number.")
        }
        guard config.duration.isFinite, config.duration > 0 else {
            throw OverlayVideoError.invalidConfiguration("Output duration must be a positive finite number.")
        }
        guard config.averageBitRate > 0 else {
            throw OverlayVideoError.invalidConfiguration("Output bitrate must be positive.")
        }
        guard config.averageBitRate <= 1_000_000_000 else {
            throw OverlayVideoError.invalidConfiguration("Output bitrate must be 1,000,000 kbps or lower.")
        }
        guard config.codec.exportMode == .overlay else {
            throw OverlayVideoError.invalidConfiguration("\(config.codec.displayName) cannot be used for transparent overlay export.")
        }
        try validateOutputURL()
    }

    static func videoOutputSettings(
        width: Int,
        height: Int,
        codec: OverlayVideoCodec,
        averageBitRate: Int,
        encoderFrameRate: Int,
        expectedSourceFrameRate: Double? = nil,
        hardwareProfile: OverlayHardwareProfile
    ) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: codec.avCodecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        if let encoderSpecification = hardwareEncoderSpecification(
            codec: codec,
            hardwareProfile: hardwareProfile
        ) {
            #if os(macOS)
            settings[AVVideoEncoderSpecificationKey] = encoderSpecification
            #endif
        }

        if codec == .hevcAlpha {
            var compressionProperties: [String: Any] = [
                AVVideoAverageBitRateKey: averageBitRate,
                AVVideoMaxKeyFrameIntervalKey: encoderFrameRate,
                AVVideoAllowFrameReorderingKey: false,
                kVTCompressionPropertyKey_RealTime as String: true,
                kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_StraightAlpha,
                kVTCompressionPropertyKey_TargetQualityForAlpha as String: 1.0
            ]
            // 软件编码器（如 iOS 模拟器）不接受该加速提示属性，传入会让 AVAssetWriterInput 直接抛异常。
            if hardwareProfile.canUseHardwareEncoder(for: codec) {
                compressionProperties[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = true
            }
            let expectedRate = expectedSourceFrameRate ?? Double(encoderFrameRate)
            if abs(expectedRate.rounded() - expectedRate) < 0.000_001 {
                compressionProperties[AVVideoExpectedSourceFrameRateKey] = expectedRate
            }
            settings[AVVideoCompressionPropertiesKey] = compressionProperties
        }

        return settings
    }

    static func prepareHEVCAlphaForEncoding(
        from source: CVPixelBuffer,
        to destination: CVPixelBuffer,
        context: CIContext,
        colorSpace: CGColorSpace
    ) {
        let width = CVPixelBufferGetWidth(destination)
        let height = CVPixelBufferGetHeight(destination)
        let image = CIImage(cvPixelBuffer: source).unpremultiplyingAlpha()
        context.render(image, to: destination, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: colorSpace)
        CVBufferSetAttachment(
            destination,
            kCVImageBufferAlphaChannelModeKey,
            kCVImageBufferAlphaChannelMode_StraightAlpha,
            .shouldPropagate
        )
    }

    static func preparePremultipliedAlphaForEncoding(on pixelBuffer: CVPixelBuffer) {
        CVBufferSetAttachment(
            pixelBuffer,
            kCVImageBufferAlphaChannelModeKey,
            kCVImageBufferAlphaChannelMode_PremultipliedAlpha,
            .shouldPropagate
        )
    }

    static func makePixelBufferPool(width: Int, height: Int, minimumBufferCount: Int) throws -> CVPixelBufferPool {
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: minimumBufferCount]
        let attributes = OverlayPixelBufferAttributes.canvas(width: width, height: height)
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, poolAttributes as CFDictionary, attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        return pool
    }

    static func makePixelBuffer(from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        return pixelBuffer
    }

    static func appendPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        to input: AVAssetWriterInput,
        at presentationTime: CMTime,
        duration: CMTime
    ) throws -> Bool {
        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        return input.append(sampleBuffer)
    }

    static func hardwareEncoderSpecification(
        codec: OverlayVideoCodec,
        hardwareProfile: OverlayHardwareProfile,
        softwareOnly: Bool = false
    ) -> [String: Any]? {
        if softwareOnly && codec.exportMode == .video {
            return [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false]
        }
        if let encoder = hardwareProfile.hardwareEncoder(for: codec) {
            var specification: [String: Any] = [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
            ]
            if let encoderID = encoder.encoderID {
                specification[kVTVideoEncoderSpecification_EncoderID as String] = encoderID
            }
            if let gpuRegistryID = encoder.gpuRegistryID {
                specification[kVTVideoEncoderSpecification_PreferredEncoderGPURegistryID as String] = NSNumber(value: gpuRegistryID)
            }
            return specification
        }

        if hardwareProfile.isAppleSiliconProcess {
            return [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true
            ]
        }

        return nil
    }

    private func validateOutputURL() throws {
        let fileManager = FileManager.default
        let directory = outputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw OverlayVideoError.invalidConfiguration("Output directory does not exist: \(directory.path)")
        }

        var outputIsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: outputURL.path, isDirectory: &outputIsDirectory),
           outputIsDirectory.boolValue {
            throw OverlayVideoError.invalidConfiguration("Output path must be a file, not a directory: \(outputURL.path)")
        }
    }

    private func encoderFrameRateValue(_ framesPerSecond: Double) throws -> Int {
        let rounded = framesPerSecond.rounded()
        guard rounded.isFinite,
              rounded >= 1,
              rounded <= Double(Int.max) else {
            throw OverlayVideoError.invalidConfiguration("Output frame rate is too large for the encoder.")
        }
        return Int(rounded)
    }

    func makeTemporaryOutputURL() -> URL {
        Self.makeTemporaryOutputURL(
            for: outputURL,
            fallbackBaseName: "datalayer-overlay",
            directory: config.temporaryDirectory
        )
    }

    static func makeTemporaryOutputURL(
        for outputURL: URL,
        tag: String? = nil,
        fallbackBaseName: String,
        directory: URL? = nil
    ) -> URL {
        let baseName = outputURL.deletingPathExtension().lastPathComponent
        let pathExtension = outputURL.pathExtension.isEmpty ? "mov" : outputURL.pathExtension
        let safeBaseName = baseName.isEmpty ? fallbackBaseName : baseName
        let tagComponent = tag.map { "\($0)-" } ?? ""
        return (directory ?? VideoExportSupport.temporaryDirectory)
            .appendingPathComponent("\(temporaryFilePrefix)\(ProcessInfo.processInfo.processIdentifier)-\(tagComponent)\(safeBaseName)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private static func shouldRemoveTemporaryOutput(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix(temporaryFilePrefix) else { return false }

        let remainder = name.dropFirst(temporaryFilePrefix.count)
        guard let separator = remainder.firstIndex(of: "-"),
              let pid = Int32(remainder[..<separator]) else {
            return true
        }
        if name.contains("-worker-") {
            if let value = try? String(contentsOf: url.appendingPathComponent("worker.pid")),
               let workerPID = Int32(value), isProcessRunning(workerPID) { return false }
            // Give an orphaned helper time to observe its parent's death before crash recovery.
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  Date().timeIntervalSince(modified) > 60 else { return false }
        }
        return !isProcessRunning(pid)
    }

    private static func isProcessRunning(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if pid == ProcessInfo.processInfo.processIdentifier {
            return true
        }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private func removePartialOutput(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func describe(error: Error?, codec: OverlayVideoCodec) -> String {
        guard let error else { return "Unknown writer failure" }
        let nsError = error as NSError
        var hint = ""
        if codec == .hevcAlpha,
           nsError.domain == AVFoundationErrorDomain,
           nsError.code == AVError.encoderNotFound.rawValue {
            hint = " The system HEVC-with-alpha encoder is unavailable on this Mac; use a Mac/OS combination with that encoder, or pass --codec prores-4444 for an alpha-capable editing intermediate."
        }
        if nsError.userInfo.isEmpty {
            return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)\(hint)"
        }
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription) \(nsError.userInfo)\(hint)"
    }

    private func diagnose(
        stage: VideoExportDiagnosticEvent.Stage,
        phase: VideoExportDiagnosticEvent.Phase,
        frameIndex: Int? = nil,
        totalFrames: Int? = nil,
        writer: AVAssetWriter? = nil,
        inputReady: Bool? = nil,
        error: Error? = nil
    ) {
        deliverDiagnostic(diagnosticEvent(
            stage: stage,
            phase: phase,
            frameIndex: frameIndex,
            totalFrames: totalFrames,
            writer: writer,
            inputReady: inputReady,
            error: error
        ))
    }

    private func diagnosticEvent(
        stage: VideoExportDiagnosticEvent.Stage,
        phase: VideoExportDiagnosticEvent.Phase,
        frameIndex: Int? = nil,
        totalFrames: Int? = nil,
        writer: AVAssetWriter? = nil,
        inputReady: Bool? = nil,
        error: Error? = nil
    ) -> VideoExportDiagnosticEvent {
        let nsError = error as NSError?
        return VideoExportDiagnosticEvent(
            stage: stage,
            phase: phase,
            frameIndex: frameIndex,
            totalFrames: totalFrames,
            writerStatus: writer.map(diagnosticWriterStatus),
            inputReady: inputReady,
            errorDomain: nsError?.domain,
            errorCode: nsError?.code
        )
    }

    private func diagnoseFailure(
        stage: VideoExportDiagnosticEvent.Stage,
        error: Error,
        frameIndex: Int? = nil,
        totalFrames: Int? = nil,
        writer: AVAssetWriter? = nil,
        inputReady: Bool? = nil
    ) {
        diagnosticDeliveryLock.lock()
        didReportPreciseFailure = true
        diagnosticDeliveryLock.unlock()

        let diagnosticError = writer?.error ?? error
        let nsError = diagnosticError as NSError
        diagnose(
            stage: stage,
            phase: .failure,
            frameIndex: frameIndex,
            totalFrames: totalFrames,
            writer: writer,
            inputReady: inputReady,
            error: nsError
        )
    }

    private var hasReportedPreciseFailure: Bool {
        diagnosticDeliveryLock.lock()
        defer { diagnosticDeliveryLock.unlock() }
        return didReportPreciseFailure
    }

    private func resetDiagnosticFailure() {
        diagnosticDeliveryLock.lock()
        didReportPreciseFailure = false
        diagnosticDeliveryLock.unlock()
    }

    private func deliverDiagnostic(_ event: VideoExportDiagnosticEvent) {
        diagnosticDeliveryLock.lock()
        if event.phase == .failure, event.stage != .exportFailed { didReportPreciseFailure = true }
        config.diagnosticsHandler?(event)
        diagnosticDeliveryLock.unlock()
    }

    private func deliverLatestRenderDiagnostic(from tracker: TransparentRenderDiagnosticStageTracker?) {
        guard let tracker else { return }
        diagnosticDeliveryLock.lock()
        if let event = tracker.takeLatest() {
            config.diagnosticsHandler?(event)
        }
        diagnosticDeliveryLock.unlock()
    }

    private func diagnosticWriterStatus(_ writer: AVAssetWriter) -> VideoExportDiagnosticEvent.WriterStatus {
        switch writer.status {
        case .unknown: return .unknown
        case .writing: return .writing
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        @unknown default: return .unknown
        }
    }
}

private final class TransparentRenderDiagnosticStageTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var reportedGeneration: UInt64 = 0
    private var event: VideoExportDiagnosticEvent?

    func update(_ event: VideoExportDiagnosticEvent) {
        lock.lock()
        generation &+= 1
        self.event = event
        lock.unlock()
    }

    func takeLatest() -> VideoExportDiagnosticEvent? {
        lock.lock()
        defer { lock.unlock() }
        guard generation != reportedGeneration, let event else { return nil }
        reportedGeneration = generation
        return event
    }
}

enum VideoExportSupport {
    // Set only by the single-job helper, so the parent can reclaim every partial file after exit.
    static var temporaryDirectory = FileManager.default.temporaryDirectory
    private static let copyChunkSize = 1_048_576
    private static let cancellationPollInterval: DispatchTimeInterval = .milliseconds(50)

    static func throwIfCancelled(_ cancellationHandler: (() -> Bool)?) throws {
        if cancellationHandler?() == true {
            throw OverlayVideoError.cancelled
        }
    }

    static func finishWriting(
        _ writer: AVAssetWriter,
        cancellationHandler: (() -> Bool)?
    ) throws {
        do {
            try throwIfCancelled(cancellationHandler)
        } catch {
            writer.cancelWriting()
            throw error
        }

        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        while finished.wait(timeout: .now() + cancellationPollInterval) == .timedOut {
            if cancellationHandler?() == true {
                writer.cancelWriting()
                finished.wait()
                throw OverlayVideoError.cancelled
            }
        }
        try throwIfCancelled(cancellationHandler)
    }

    static func waitForExport(
        _ exportSession: AVAssetExportSession,
        cancellationHandler: (() -> Bool)?,
        progressHandler: (() -> Void)? = nil
    ) throws {
        try throwIfCancelled(cancellationHandler)
        let finished = DispatchSemaphore(value: 0)
        exportSession.exportAsynchronously { finished.signal() }
        var nextProgressUpdate = ProcessInfo.processInfo.systemUptime + 1
        while finished.wait(timeout: .now() + cancellationPollInterval) == .timedOut {
            let uptime = ProcessInfo.processInfo.systemUptime
            if uptime >= nextProgressUpdate {
                progressHandler?()
                nextProgressUpdate = uptime + 1
            }
            if cancellationHandler?() == true {
                exportSession.cancelExport()
                finished.wait()
                throw OverlayVideoError.cancelled
            }
        }
        try throwIfCancelled(cancellationHandler)
    }

    static func installCompletedOutput(
        from completedURL: URL,
        to outputURL: URL,
        cancellationHandler: (() -> Bool)?,
        diagnosticsHandler: ((VideoExportDiagnosticEvent) -> Void)? = nil,
        replaceItem: (URL, URL) throws -> Void = { outputURL, completedURL in
            _ = try FileManager.default.replaceItemAt(
                outputURL,
                withItemAt: completedURL,
                backupItemName: nil
            )
        }
    ) throws {
        let fileManager = FileManager.default
        var step = VideoExportDiagnosticEvent.OperationStep.outputCheckCompleted
        var failureHints: VideoExportFileSystemHints?
        func checkpoint(_ value: VideoExportDiagnosticEvent.OperationStep) {
            step = value
            diagnosticsHandler?(.init(stage: .installOutput, phase: .update, operationStep: value))
        }
        do {
            try throwIfCancelled(cancellationHandler)
            checkpoint(.outputCheckCompleted)
            try FileHandle(forReadingFrom: completedURL).close()

            if fileManager.fileExists(atPath: outputURL.path) {
                // 沙盒下 NSSavePanel 只授权用户选中的文件本身，不授权它所在的目录。
                // 传 backupItemName 会让 FileManager 在目标目录新建一个同级备份文件，
                // 越权触发 NSFileWriteNoPermission；而替换此时已经完成，表现为
                // "文件已正确替换但报导出失败"。backupItemName 为 nil 时原件暂存在
                // FileManager 自己的临时目录，同样是原子替换，且不碰用户目录。
                do {
                    checkpoint(.outputReplace)
                    try replaceItem(outputURL, completedURL)
                    return
                } catch {
                    // 替换若已经生效（源文件被消费），即使随后抛错也不应判为失败。
                    if !fileManager.fileExists(atPath: completedURL.path) {
                        return
                    }
                    let native = error as NSError
                    let posix = native.domain == NSPOSIXErrorDomain ? native : native.userInfo[NSUnderlyingErrorKey] as? NSError
                    guard posix?.domain == NSPOSIXErrorDomain, posix?.code == Int(EXDEV) else { throw error }

                    // 原子替换要求同卷；系统替换目录不需要在用户目标目录创建同级文件。
                    checkpoint(.outputCopy)
                    let directory = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                        appropriateFor: outputURL, create: true)
                    defer { try? fileManager.removeItem(at: directory) }
                    let replacementURL = directory.appendingPathComponent(completedURL.lastPathComponent)
                    try copyFile(
                        from: completedURL, to: replacementURL, cancellationHandler: cancellationHandler,
                        failureHandler: { error, failedStep in
                            step = failedStep
                            failureHints = .capture(sourceURL: completedURL, targetURL: replacementURL, error: error)
                        }
                    )
                    try throwIfCancelled(cancellationHandler)
                    checkpoint(.outputReplace)
                    do {
                        try replaceItem(outputURL, replacementURL)
                    } catch {
                        if fileManager.fileExists(atPath: replacementURL.path) {
                            failureHints = .capture(sourceURL: replacementURL, targetURL: outputURL, error: error)
                            throw error
                        }
                    }
                    try? fileManager.removeItem(at: completedURL)
                    return
                }
            }

            do {
                checkpoint(.outputMove)
                try fileManager.moveItem(at: completedURL, to: outputURL)
                do {
                    try throwIfCancelled(cancellationHandler)
                } catch {
                    try? fileManager.removeItem(at: outputURL)
                    throw error
                }
            } catch OverlayVideoError.cancelled {
                throw OverlayVideoError.cancelled
            } catch {
                try? fileManager.removeItem(at: outputURL)
                checkpoint(.outputCopy)
                try copyFile(
                    from: completedURL,
                    to: outputURL,
                    cancellationHandler: cancellationHandler,
                    failureHandler: { error, failedStep in
                        step = failedStep
                        failureHints = .capture(sourceURL: completedURL, targetURL: outputURL, error: error)
                    }
                )
                try? fileManager.removeItem(at: completedURL)
            }
        } catch OverlayVideoError.cancelled {
            throw OverlayVideoError.cancelled
        } catch {
            if let diagnosticsHandler {
                let native = error as NSError
                diagnosticsHandler(.init(stage: .installOutput, phase: .failure,
                    errorDomain: native.domain, errorCode: native.code, operationStep: step,
                    fileSystemHints: failureHints ?? .capture(sourceURL: completedURL, targetURL: outputURL, error: error)))
            }
            throw error
        }
    }

    private static func copyFile(
        from sourceURL: URL,
        to destinationURL: URL,
        cancellationHandler: (() -> Bool)?,
        failureHandler: ((Error, VideoExportDiagnosticEvent.OperationStep) -> Void)? = nil
    ) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destinationURL)
        var step = VideoExportDiagnosticEvent.OperationStep.outputCreateFile
        var createdDestination = false
        do {
            try Data().write(to: destinationURL, options: .withoutOverwriting)
            createdDestination = true
            step = .outputOpenSource
            let source = try FileHandle(forReadingFrom: sourceURL)
            step = .outputOpenTarget
            let destination = try FileHandle(forWritingTo: destinationURL)
            defer {
                try? source.close()
                try? destination.close()
            }

            while true {
                try throwIfCancelled(cancellationHandler)
                step = .outputReadSource
                guard let chunk = try source.read(upToCount: copyChunkSize), !chunk.isEmpty else {
                    break
                }
                step = .outputWriteTarget
                try destination.write(contentsOf: chunk)
            }
            step = .outputSynchronize
            try destination.synchronize()
            try throwIfCancelled(cancellationHandler)
        } catch {
            failureHandler?(error, step)
            if createdDestination { try? fileManager.removeItem(at: destinationURL) }
            throw error
        }
    }
}
