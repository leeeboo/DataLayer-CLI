import AudioToolbox
import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import VideoToolbox

public struct CompositedVideoWriterConfig {
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
    var softwareDecoding = false
    var softwareEncoding = false

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
        codec: OverlayVideoCodec = .hevc,
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

public final class CompositedVideoWriter {
    private let outputURL: URL
    private let sourceAsset: AVAsset?
    private let sourceDescription: String
    private let sourceVideoSegments: [TimelineVideoSegment]
    private let usesTimelineSegmentReader: Bool
    private let series: TelemetrySeries?
    private let config: CompositedVideoWriterConfig
    private let overlayStartTime: TimeInterval
    private let renderOverlay: ((TimeInterval, CVPixelBuffer) throws -> Void)?
    private let segmentReaderAttemptFactory: ResilientTimelineSegmentReader.AttemptFactory?
    private let diagnosticDeliveryLock = NSLock()
    private let exportWarningLock = NSLock()
    private var exportWarnings: [VideoExportWarning] = []
    private var skippedVideoRanges: [CMTimeRange] = []
    private var audioSampleReader: (AVAssetReaderOutput) throws -> CMSampleBuffer? = { $0.copyNextSampleBuffer() }

    public init(outputURL: URL, sourceVideoURL: URL, series: TelemetrySeries, config: CompositedVideoWriterConfig) {
        self.outputURL = outputURL
        self.sourceAsset = AVURLAsset(url: sourceVideoURL)
        self.sourceDescription = sourceVideoURL.path
        self.sourceVideoSegments = []
        self.usesTimelineSegmentReader = false
        self.series = series
        self.config = config
        self.overlayStartTime = config.startTime
        self.renderOverlay = nil
        self.segmentReaderAttemptFactory = nil
    }

    init(
        outputURL: URL,
        sourceVideoURL: URL,
        config: CompositedVideoWriterConfig,
        overlayStartTime: TimeInterval,
        renderOverlay: @escaping (TimeInterval, CVPixelBuffer) throws -> Void
    ) {
        self.outputURL = outputURL
        self.sourceAsset = AVURLAsset(url: sourceVideoURL)
        self.sourceDescription = sourceVideoURL.path
        self.sourceVideoSegments = []
        self.usesTimelineSegmentReader = false
        self.series = nil
        self.config = config
        self.overlayStartTime = overlayStartTime
        self.renderOverlay = renderOverlay
        self.segmentReaderAttemptFactory = nil
    }

    init(
        outputURL: URL,
        sourceAsset: AVAsset,
        sourceDescription: String,
        sourceVideoSegments: [TimelineVideoSegment] = [],
        config: CompositedVideoWriterConfig,
        overlayStartTime: TimeInterval,
        renderOverlay: @escaping (TimeInterval, CVPixelBuffer) throws -> Void,
        initialWarnings: [VideoExportWarning] = [],
        segmentReaderAttemptFactory: ResilientTimelineSegmentReader.AttemptFactory? = nil,
        audioSampleReader: ((AVAssetReaderOutput) throws -> CMSampleBuffer?)? = nil
    ) {
        self.outputURL = outputURL
        self.sourceAsset = sourceAsset
        self.sourceDescription = sourceDescription
        self.sourceVideoSegments = sourceVideoSegments
        self.usesTimelineSegmentReader = true
        self.series = nil
        self.config = config
        self.overlayStartTime = overlayStartTime
        self.renderOverlay = renderOverlay
        self.segmentReaderAttemptFactory = segmentReaderAttemptFactory
        if let audioSampleReader { self.audioSampleReader = audioSampleReader }
        self.exportWarnings = initialWarnings
        self.skippedVideoRanges = initialWarnings.compactMap { warning in
            guard warning.kind == .videoSegmentSkipped else { return nil }
            return CMTimeRange(
                start: CMTime(seconds: warning.timelineStart, preferredTimescale: 60_000),
                duration: CMTime(seconds: warning.duration, preferredTimescale: 60_000)
            )
        }
    }

    init(
        outputURL: URL,
        config: CompositedVideoWriterConfig,
        overlayStartTime: TimeInterval,
        renderOverlay: @escaping (TimeInterval, CVPixelBuffer) throws -> Void
    ) {
        self.outputURL = outputURL
        self.sourceAsset = nil
        self.sourceDescription = "black timeline canvas"
        self.sourceVideoSegments = []
        self.usesTimelineSegmentReader = false
        self.series = nil
        self.config = config
        self.overlayStartTime = overlayStartTime
        self.renderOverlay = renderOverlay
        self.segmentReaderAttemptFactory = nil
    }

    @discardableResult
    public func write() throws -> VideoExportResult {
        try VideoExportCleanup.check()
        #if os(macOS)
        return try VideoExportSupport.performWriting(
            cancellationHandler: config.cancellationHandler,
            progressHandler: config.progressHandler,
            diagnosticsHandler: config.diagnosticsHandler,
            securityScopedURLs: [outputURL] + ((sourceAsset as? AVURLAsset).map { [$0.url] } ?? [])
        ) { control in
            var config = self.config
            config.cancellationHandler = { control.isCancelled }
            config.progressHandler = control.recordProgress
            config.diagnosticsHandler = control.recordDiagnostic
            return try CompositedVideoWriter(copying: self, config: config).writeUnmonitored()
        }
        #else
        return try writeUnmonitored()
        #endif
    }

    private init(copying writer: CompositedVideoWriter, config: CompositedVideoWriterConfig) {
        outputURL = writer.outputURL
        sourceAsset = writer.sourceAsset
        sourceDescription = writer.sourceDescription
        sourceVideoSegments = writer.sourceVideoSegments
        usesTimelineSegmentReader = writer.usesTimelineSegmentReader
        series = writer.series
        self.config = config
        overlayStartTime = writer.overlayStartTime
        renderOverlay = writer.renderOverlay
        segmentReaderAttemptFactory = writer.segmentReaderAttemptFactory
        exportWarnings = writer.exportWarnings
        skippedVideoRanges = writer.skippedVideoRanges
        audioSampleReader = writer.audioSampleReader
    }

    @discardableResult
    func writeUnmonitored() throws -> VideoExportResult {
        diagnose(
            stage: .prepareTimeline,
            phase: .begin,
            preparationStep: .initializeCompositedWriter
        )
        if config.cancellationHandler?() == true {
            diagnoseFailure(stage: .exportFailed, error: OverlayVideoError.cancelled)
            throw OverlayVideoError.cancelled
        }

        TransparentVideoWriter.removeStaleTemporaryOutputs()
        let videoOnlyURL = makeTemporaryOutputURL(tag: "video")
        let finalURL = makeTemporaryOutputURL(tag: "final")
        removePartialOutput(at: videoOnlyURL)
        removePartialOutput(at: finalURL)

        do {
            do {
                try writeMovie(to: finalURL, includeAudio: true)
            } catch let failure as AudioExportFailure {
                try VideoExportSupport.throwIfCancelled(config.cancellationHandler)
                // Preserve the established passthrough/reencode/silence recovery for unreadable audio.
                var underlying: NSError? = failure.underlying as NSError
                while let error = underlying {
                    if error.domain == NSCocoaErrorDomain || error.domain == NSPOSIXErrorDomain { throw failure.underlying }
                    underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
                }
                removePartialOutput(at: finalURL)
                try writeMovie(to: videoOnlyURL, includeAudio: false)
                try muxOriginalAudio(videoURL: videoOnlyURL, outputURL: finalURL)
            }
            try VideoExportSupport.throwIfCancelled(config.cancellationHandler)
            diagnose(stage: .installOutput, phase: .begin)
            try VideoExportSupport.installCompletedOutput(
                from: finalURL, to: outputURL, cancellationHandler: config.cancellationHandler,
                diagnosticsHandler: config.diagnosticsHandler == nil ? nil : deliverDiagnostic
            )
            diagnose(stage: .installOutput, phase: .end)
        } catch {
            diagnoseFailure(stage: .exportFailed, error: error)
            removePartialOutput(at: videoOnlyURL)
            removePartialOutput(at: finalURL)
            throw error
        }
        removePartialOutput(at: videoOnlyURL)
        removePartialOutput(at: finalURL)
        diagnose(stage: .exportCompleted, phase: .end)
        return currentExportResult()
    }

    private func writeMovie(to temporaryOutputURL: URL, includeAudio: Bool) throws {
        try validateConfiguration()

        let width = config.width
        let height = config.height
        let timing = TransparentVideoFrameTiming(
            framesPerSecond: config.framesPerSecond,
            duration: config.duration
        )
        guard !timing.frameCountWasClamped else {
            throw OverlayVideoError.invalidConfiguration(
                "Output duration and frame rate produce too many frames. Lower the duration or frame rate."
            )
        }
        let encoderFrameRate = try encoderFrameRateValue(timing.framesPerSecond)
        diagnose(
            stage: .prepareTimeline,
            phase: .end,
            totalFrames: timing.frameCount,
            preparationStep: .initializeCompositedWriter
        )

        let trimStartTime = CMTime(seconds: config.startTime, preferredTimescale: timing.mediaTimeScale)
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let reader: AVAssetReader?
        let readerOutput: AVAssetReaderTrackOutput?
        let sourceTransform: CGAffineTransform
        let sourceColorInfo: VideoColorInfo?
        if let sourceAsset, !usesTimelineSegmentReader {
            diagnose(stage: .prepareReader, phase: .begin)
            let sourceDiagnostic = sourceMetadata(for: sourceAsset)
            let videoTracks = sourceAsset.tracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                throw OverlayVideoError.unreadableVideo("No video track found in \(sourceDescription).")
            }
            sourceColorInfo = (videoTrack.formatDescriptions as? [CMFormatDescription])?.first
                .flatMap { VideoColorInfo.read(from: $0) }
            let newReader = try AVAssetReader(asset: sourceAsset)
            newReader.timeRange = CMTimeRange(start: trimStartTime, duration: timing.outputDuration)
            let newOutput = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: readerSettings
            )
            sourceTransform = makeSourceTransform(track: videoTrack, width: width, height: height)
            newOutput.alwaysCopiesSampleData = false
            diagnose(stage: .prepareReader, phase: .update, reader: newReader, source: sourceDiagnostic)
            guard newReader.canAdd(newOutput) else {
                throw OverlayVideoError.unreadableVideo("Could not read composited video frames from \(sourceDescription).")
            }
            newReader.add(newOutput)
            reader = newReader
            readerOutput = newOutput
        } else if usesTimelineSegmentReader {
            // Timeline video is read lazily from one original source segment at a time below.
            // Keep the composition only for its already-timeline-mapped audio.
            sourceColorInfo = nil
            reader = nil
            readerOutput = nil
            sourceTransform = .identity
        } else {
            sourceColorInfo = nil
            reader = nil
            readerOutput = nil
            sourceTransform = .identity
        }

        let hardwareProfile = OverlayHardwareProfile.current
        diagnose(stage: .prepareWriter, phase: .begin)
        let writer = try AVAssetWriter(outputURL: temporaryOutputURL, fileType: .mov)
        var audioStreams: [CompositedAudioStream] = []
        defer {
            audioStreams.forEach { if $0.reader.status == .reading { $0.reader.cancelReading() } }
            if writer.status == .writing { writer.cancelWriting() }
        }
        writer.movieTimeScale = timing.mediaTimeScale
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(
                width: width,
                height: height,
                codec: config.codec,
                averageBitRate: config.averageBitRate,
                encoderFrameRate: encoderFrameRate,
                expectedSourceFrameRate: timing.framesPerSecond,
                hardwareProfile: hardwareProfile
            )
        )
        input.mediaTimeScale = timing.mediaTimeScale
        input.expectsMediaDataInRealTime = false
        input.performsMultiPassEncodingIfSupported = false
        guard writer.canAdd(input) else {
            throw OverlayVideoError.unsupportedEncoder(
                "This macOS installation cannot add a \(config.codec.displayName) video writer input."
            )
        }
        writer.add(input)
        if includeAudio { audioStreams = try makeAudioStreams(writer: writer, duration: timing.outputDuration) }

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: OverlayPixelBufferAttributes.canvas(width: width, height: height)
        )

        if let reader, !reader.startReading() {
            throw OverlayVideoError.unreadableVideo(reader.error?.localizedDescription ?? "Could not start reading source video.", underlying: reader.error)
        }
        if let reader {
            diagnose(stage: .prepareReader, phase: .end, reader: reader)
        }
        guard writer.startWriting() else {
            let error = OverlayVideoError.cannotStartWriter(describe(error: writer.error, codec: config.codec), underlying: writer.error)
            diagnoseFailure(stage: .prepareWriter, error: error)
            throw error
        }
        writer.startSession(atSourceTime: .zero)
        diagnose(stage: .prepareWriter, phase: .end, writer: writer)

        let renderer = series.map {
            OverlayRenderer(
                series: $0,
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
        }
        let colorSpace = VideoColorPipeline.outputColorSpace
        let ciContext = VideoColorPipeline.makeContext()
        let overlayPool = try TransparentVideoWriter.makePixelBufferPool(width: width, height: height, minimumBufferCount: 2)
        let outputBounds = CGRect(x: 0, y: 0, width: width, height: height)
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: outputBounds)

        let renderQueue = DispatchQueue(label: "run.libo.overlay.composited-writer")
        let writeFinished = DispatchSemaphore(value: 0)
        let codec = config.codec
        let progressHandler = config.progressHandler
        let cancellationHandler = config.cancellationHandler
        let timelineVideoSegments = sourceVideoSegments
        let frameCount = timing.frameCount
        var frameIndex = 0
        var writeError: Error?
        var didFinishInput = false
        var didSignalCompletion = false
        var currentSourceSample: CMSampleBuffer?
        var pendingSourceSample: CMSampleBuffer?
        var timelineSegmentIndex = 0
        var activeTimelineSegmentIndex: Int?
        let lazySegmentReader = timelineVideoSegments.isEmpty ? nil : ResilientTimelineSegmentReader(
            videoSettings: readerSettings,
            initialStrategy: config.softwareDecoding ? .softwareWithPreroll : .primary,
            warningHandler: { [weak self] warning in
                self?.recordExportWarning(warning)
            },
            attemptFactory: segmentReaderAttemptFactory,
            diagnosticsHandler: config.diagnosticsHandler == nil ? nil : { [weak self] event in
                self?.deliverDiagnostic(event)
            }
        )
        let renderDiagnosticTracker = config.diagnosticsHandler.map { _ in
            RenderDiagnosticStageTracker()
        }

        let reportLatestRenderDiagnostic: () -> Void = {
            guard let renderDiagnosticTracker else { return }
            self.deliverLatestRenderDiagnostic(from: renderDiagnosticTracker)
        }
        let captureLatestRenderDiagnostic: () -> Void = {
            renderDiagnosticTracker?.markLatestReported()
        }

        // All producer state is confined to the serial render queue, including audio EOF and errors.
        func finishInputs() {
            if (frameIndex >= frameCount || writeError != nil), !didFinishInput {
                didFinishInput = true
                captureLatestRenderDiagnostic()
                self.diagnose(stage: .finishInput, phase: .begin, frameIndex: frameIndex, totalFrames: frameCount, writer: writer)
                input.markAsFinished()
                self.diagnose(stage: .finishInput, phase: .end, frameIndex: frameIndex, totalFrames: frameCount, writer: writer)
            }
            if writeError != nil {
                for stream in audioStreams where !stream.finished {
                    stream.finished = true
                    stream.input.markAsFinished()
                }
            }
            if didFinishInput, audioStreams.allSatisfy({ $0.finished }), !didSignalCompletion {
                didSignalCompletion = true
                writeFinished.signal()
            }
        }

        diagnose(stage: .awaitReady, phase: .begin, totalFrames: frameCount)
        input.requestMediaDataWhenReady(on: renderQueue) {
            renderDiagnosticTracker?.update(self.diagnosticEvent(
                stage: .awaitReady,
                phase: .update,
                frameIndex: frameIndex,
                totalFrames: frameCount,
                inputReady: input.isReadyForMoreMediaData
            ))
            while input.isReadyForMoreMediaData,
                  frameIndex < frameCount,
                  writeError == nil {
                do {
                    try autoreleasepool {
                        if cancellationHandler?() == true {
                            throw OverlayVideoError.cancelled
                        }

                        guard let pool = adaptor.pixelBufferPool else {
                            throw OverlayVideoError.cannotCreatePixelBuffer
                        }
                        let presentationTime = timing.presentationTime(for: frameIndex)
                        let sourceTime = CMTimeAdd(trimStartTime, presentationTime)
                        var sourceImage = background
                        let tolerance = CMTimeMultiplyByFloat64(timing.frameDuration, multiplier: 0.5)
                        if let lazySegmentReader {
                            while timelineSegmentIndex < timelineVideoSegments.count,
                                  sourceTime >= CMTimeRangeGetEnd(
                                    timelineVideoSegments[timelineSegmentIndex].timelineRange
                                  ) {
                                timelineSegmentIndex += 1
                            }
                            let segmentIndex: Int? = timelineSegmentIndex < timelineVideoSegments.count
                                && CMTimeRangeContainsTime(
                                    timelineVideoSegments[timelineSegmentIndex].timelineRange,
                                    time: sourceTime
                                )
                                ? timelineSegmentIndex
                                : nil

                            if segmentIndex != activeTimelineSegmentIndex {
                                currentSourceSample = nil
                                pendingSourceSample = nil
                                // Release decoded buffers before closing the old reader. Retaining
                                // them can keep its hardware decoder alive while the next segment's
                                // differently encoded reader is being started.
                                lazySegmentReader.close()
                                activeTimelineSegmentIndex = segmentIndex
                                if let segmentIndex {
                                    let segment = timelineVideoSegments[segmentIndex]
                                    self.diagnose(
                                        stage: .prepareReader,
                                        phase: .begin,
                                        source: self.sourceMetadata(for: segment.asset)
                                    )
                                    try lazySegmentReader.open(segment, sourceIndex: segmentIndex + 1)
                                    self.diagnose(
                                        stage: .prepareReader,
                                        phase: .end,
                                        reader: lazySegmentReader.reader
                                    )
                                }
                            }

                            if let segmentIndex {
                                let segment = timelineVideoSegments[segmentIndex]
                                let requestedSourceTime = CMTimeAdd(
                                    segment.sourceRange.start,
                                    CMTimeSubtract(sourceTime, segment.timelineRange.start)
                                )
                                let latestAcceptedTime = CMTimeAdd(requestedSourceTime, tolerance)
                                while true {
                                    if pendingSourceSample == nil {
                                        renderDiagnosticTracker?.update(self.diagnosticEvent(
                                            stage: .readSource,
                                            phase: .begin,
                                            frameIndex: frameIndex,
                                            totalFrames: frameCount,
                                            reader: lazySegmentReader.reader
                                        ))
                                        pendingSourceSample = try lazySegmentReader.copyNextSampleBuffer(
                                            targetSourceTime: requestedSourceTime
                                        )
                                    }
                                    guard let sample = pendingSourceSample else { break }
                                    let sampleTime = CMSampleBufferGetPresentationTimeStamp(sample)
                                    guard sampleTime <= latestAcceptedTime else { break }
                                    currentSourceSample = sample
                                    pendingSourceSample = nil
                                }
                                if let currentSourceSample,
                                   let sourceBuffer = CMSampleBufferGetImageBuffer(currentSourceSample) {
                                    sourceImage = try VideoColorPipeline.process(
                                        pixelBuffer: sourceBuffer,
                                        sourceInfo: segment.sourceInfo,
                                        settings: segment.colorSettings,
                                        lut: segment.lut
                                    )
                                        .transformed(by: segment.sourceTransform)
                                        .composited(over: background)
                                }
                            }
                        } else if let readerOutput {
                            let latestAcceptedTime = CMTimeAdd(sourceTime, tolerance)
                            while true {
                                if pendingSourceSample == nil {
                                    renderDiagnosticTracker?.update(self.diagnosticEvent(
                                        stage: .readSource,
                                        phase: .begin,
                                        frameIndex: frameIndex,
                                        totalFrames: frameCount,
                                        reader: reader
                                    ))
                                    pendingSourceSample = readerOutput.copyNextSampleBuffer()
                                }
                                guard let sample = pendingSourceSample else { break }
                                let sampleTime = CMSampleBufferGetPresentationTimeStamp(sample)
                                guard sampleTime <= latestAcceptedTime else { break }
                                currentSourceSample = sample
                                pendingSourceSample = nil
                            }
                            if let currentSourceSample,
                               let sourceBuffer = CMSampleBufferGetImageBuffer(currentSourceSample) {
                                sourceImage = try VideoColorPipeline.process(
                                    pixelBuffer: sourceBuffer,
                                    sourceInfo: sourceColorInfo,
                                    settings: nil,
                                    lut: nil
                                )
                                    .transformed(by: sourceTransform)
                                    .composited(over: background)
                            }
                        }

                        let outputBuffer = try TransparentVideoWriter.makePixelBuffer(from: pool)
                        let overlayBuffer = try TransparentVideoWriter.makePixelBuffer(from: overlayPool)
                        let overlayTime = self.overlayStartTime + CMTimeGetSeconds(presentationTime)

                        renderDiagnosticTracker?.update(self.diagnosticEvent(
                            stage: .renderOverlay,
                            phase: .begin,
                            frameIndex: frameIndex,
                            totalFrames: frameCount
                        ))
                        if let renderOverlay = self.renderOverlay {
                            try renderOverlay(overlayTime, overlayBuffer)
                        } else if let renderer {
                            try renderer.render(videoTime: overlayTime, into: overlayBuffer)
                        }
                        let composed = CIImage(cvPixelBuffer: overlayBuffer)
                            .composited(over: sourceImage)
                        renderDiagnosticTracker?.update(self.diagnosticEvent(
                            stage: .ciComposite,
                            phase: .begin,
                            frameIndex: frameIndex,
                            totalFrames: frameCount
                        ))
                        ciContext.render(
                            composed,
                            to: outputBuffer,
                            bounds: outputBounds,
                            colorSpace: colorSpace
                        )
                        VideoColorPipeline.markOutput(outputBuffer)
                        renderDiagnosticTracker?.update(self.diagnosticEvent(
                            stage: .appendFrame,
                            phase: .begin,
                            frameIndex: frameIndex,
                            totalFrames: frameCount,
                            inputReady: input.isReadyForMoreMediaData
                        ))
                        guard try TransparentVideoWriter.appendPixelBuffer(
                            outputBuffer,
                            to: input,
                            at: presentationTime,
                            duration: timing.frameDuration
                        ) else {
                            throw OverlayVideoError.writerFailed(self.describe(error: writer.error, codec: codec), underlying: writer.error)
                        }
                        frameIndex += 1
                        if frameIndex == 1
                            || frameIndex == frameCount
                            || frameIndex % Int(max(1, timing.framesPerSecond)) == 0 {
                            progressHandler?(frameIndex, frameCount)
                        }
                    }
                } catch OverlayVideoError.cancelled {
                    writeError = OverlayVideoError.cancelled
                } catch {
                    self.diagnoseFailure(stage: renderDiagnosticTracker?.currentStage ?? .appendFrame, error: error)
                    writeError = error
                }
            }

            if frameIndex < frameCount, writeError == nil {
                renderDiagnosticTracker?.update(self.diagnosticEvent(
                    stage: .awaitReady,
                    phase: .update,
                    frameIndex: frameIndex,
                    totalFrames: frameCount,
                    inputReady: input.isReadyForMoreMediaData
                ))
            }

            finishInputs()
        }
        for stream in audioStreams {
            stream.input.requestMediaDataWhenReady(on: renderQueue) {
                guard !stream.finished else { return }
                while stream.input.isReadyForMoreMediaData, writeError == nil, !stream.finished {
                    do {
                        try autoreleasepool {
                            try VideoExportSupport.throwIfCancelled(cancellationHandler)
                            renderDiagnosticTracker?.update(self.diagnosticEvent(stage: .readAudio, phase: .begin, reader: stream.reader))
                            let sample = try stream.pendingSample ?? self.audioSampleReader(stream.output)
                            stream.pendingSample = nil
                            try VideoExportSupport.throwIfCancelled(cancellationHandler)
                            guard let sample else {
                                if stream.reader.status == .failed {
                                    throw OverlayVideoError.unreadableVideo("Source audio reading failed.", underlying: stream.reader.error)
                                }
                                stream.finished = true
                                stream.input.markAsFinished()
                                return
                            }
                            renderDiagnosticTracker?.update(self.diagnosticEvent(stage: .appendAudio, phase: .begin, writer: writer))
                            guard stream.input.append(sample) else {
                                throw OverlayVideoError.writerFailed("Could not append source audio.", underlying: writer.error)
                            }
                        }
                    } catch OverlayVideoError.cancelled {
                        writeError = OverlayVideoError.cancelled
                    } catch {
                        self.diagnoseFailure(stage: renderDiagnosticTracker?.currentStage ?? .readAudio, error: error)
                        writeError = AudioExportFailure(underlying: error)
                    }
                }
                finishInputs()
            }
        }
        VideoExportSupport.waitForRenderCompletion(
            writeFinished,
            cancellationHandler: cancellationHandler,
            heartbeatHandler: reportLatestRenderDiagnostic,
            cancelProducer: {
                // Wake the segment consumer immediately; its decoder queue owns deferred
                // AVAssetReader cleanup after any in-flight copy returns.
                lazySegmentReader?.cancelReading()
                reader?.cancelReading()
                audioStreams.forEach { $0.reader.cancelReading() }
                renderQueue.async {
                    writeError = OverlayVideoError.cancelled
                    finishInputs()
                }
            }
        )
        diagnose(stage: .awaitReady, phase: .end, frameIndex: frameIndex, totalFrames: frameCount, reader: reader, writer: writer)
        // Release render-owned samples on their queue. Decoder teardown stays on the
        // segment reader's own queue and never cancels an in-flight AVFoundation copy.
        if let lazySegmentReader {
            renderQueue.sync {
                currentSourceSample = nil
                pendingSourceSample = nil
                lazySegmentReader.close()
            }
        }

        if let writeError {
            reader?.cancelReading()
            writer.cancelWriting()
            throw writeError
        }
        try VideoExportSupport.throwIfCancelled(cancellationHandler)
        if let reader, reader.status == .failed {
            writer.cancelWriting()
            let error = OverlayVideoError.unreadableVideo(reader.error?.localizedDescription ?? "Source video reading failed.", underlying: reader.error)
            diagnoseFailure(stage: .readSource, error: error)
            throw error
        }
        if reader?.status == .reading {
            reader?.cancelReading()
        }
        guard frameIndex > 0 else {
            writer.cancelWriting()
            throw OverlayVideoError.unreadableVideo("No video frames could be read from \(sourceDescription).")
        }

        writer.endSession(atSourceTime: timing.outputDuration)
        diagnose(stage: .finishWriter, phase: .begin, writer: writer)
        do {
            try VideoExportSupport.finishWriting(writer, cancellationHandler: cancellationHandler)
            guard writer.status == .completed else {
                throw OverlayVideoError.writerFailed(describe(error: writer.error, codec: config.codec), underlying: writer.error)
            }
        } catch OverlayVideoError.cancelled {
            throw OverlayVideoError.cancelled
        } catch {
            diagnoseFailure(stage: .finishWriter, error: error)
            throw error
        }
        diagnose(stage: .finishWriter, phase: .end, writer: writer)
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
        guard config.codec.exportMode == .video else {
            throw OverlayVideoError.invalidConfiguration("\(config.codec.displayName) cannot be used for composited video export.")
        }
        try validateOutputURL()
    }

    private func makeSourceTransform(track: AVAssetTrack, width: Int, height: Int) -> CGAffineTransform {
        makeSourceTransform(
            naturalSize: track.naturalSize,
            preferredTransform: track.preferredTransform,
            width: width,
            height: height
        )
    }

    private func makeSourceTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        width: Int,
        height: Int
    ) -> CGAffineTransform {
        let outputSize = CGSize(width: width, height: height)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let scale = min(outputSize.width / max(1, displaySize.width), outputSize.height / max(1, displaySize.height))
        let x = -transformedRect.minX * scale + (outputSize.width - displaySize.width * scale) / 2
        let y = -transformedRect.minY * scale + (outputSize.height - displaySize.height * scale) / 2
        let transform = preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
        return transform
    }

    private func recordExportWarning(_ warning: VideoExportWarning) {
        exportWarningLock.lock()
        defer { exportWarningLock.unlock() }
        guard !exportWarnings.contains(warning) else { return }
        exportWarnings.append(warning)
        if warning.kind == .videoSegmentSkipped {
            skippedVideoRanges.append(CMTimeRange(
                start: CMTime(seconds: warning.timelineStart, preferredTimescale: 60_000),
                duration: CMTime(seconds: warning.duration, preferredTimescale: 60_000)
            ))
        }
    }

    private func currentExportResult() -> VideoExportResult {
        exportWarningLock.lock()
        defer { exportWarningLock.unlock() }
        return VideoExportResult(warnings: exportWarnings)
    }

    private func skippedVideoRangesSnapshot() -> [CMTimeRange] {
        exportWarningLock.lock()
        defer { exportWarningLock.unlock() }
        return skippedVideoRanges
    }

    private func makeAudioStreams(writer: AVAssetWriter, duration: CMTime) throws -> [CompositedAudioStream] {
        guard let sourceAsset, hasAudioTrack(in: sourceAsset) else { return [] }
        var readers: [AVAssetReader] = []
        var prepared = false
        defer { if !prepared { readers.forEach { $0.cancelReading() } } }
        do {
            let composition = try makeAudioComposition(duration: duration, excludingAudioRanges: [])
            var streams: [CompositedAudioStream] = []
            for track in composition.tracks(withMediaType: .audio) {
                try VideoExportSupport.throwIfCancelled(config.cancellationHandler)
                let reader = try AVAssetReader(asset: composition)
                readers.append(reader)
                reader.timeRange = CMTimeRange(start: .zero, duration: duration)
                // Decode each logical track separately so parallel source audio remains separate.
                let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
                ])
                output.alwaysCopiesSampleData = false
                guard reader.canAdd(output) else { throw OverlayVideoError.unreadableVideo("Could not read source audio.") }
                reader.add(output)
                diagnose(stage: .readAudio, phase: .begin, reader: reader)
                try VideoExportSupport.throwIfCancelled(config.cancellationHandler)
                guard reader.startReading() else {
                    throw OverlayVideoError.unreadableVideo("Could not start reading source audio.", underlying: reader.error)
                }
                let firstSample = try audioSampleReader(output)
                try VideoExportSupport.throwIfCancelled(config.cancellationHandler)
                guard let firstSample else {
                    if reader.status == .failed {
                        throw OverlayVideoError.unreadableVideo("Source audio reading failed.", underlying: reader.error)
                    }
                    continue
                }
                guard let format = CMSampleBufferGetFormatDescription(firstSample),
                      let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
                    throw OverlayVideoError.unreadableVideo("Source audio has no format description.")
                }
                var settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: description.mSampleRate,
                    AVNumberOfChannelsKey: Int(description.mChannelsPerFrame), AVEncoderBitRatePerChannelKey: 96_000
                ]
                if description.mChannelsPerFrame > 2 {
                    var size = 0
                    guard let layout = CMAudioFormatDescriptionGetChannelLayout(format, sizeOut: &size), size > 0 else {
                        throw OverlayVideoError.unreadableVideo("Source audio has no multichannel layout.")
                    }
                    settings[AVChannelLayoutKey] = Data(bytes: layout, count: size)
                }
                guard writer.canApply(outputSettings: settings, forMediaType: .audio) else {
                    throw OverlayVideoError.unsupportedEncoder("Could not encode source audio.")
                }
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: format)
                input.expectsMediaDataInRealTime = false
                guard writer.canAdd(input) else { throw OverlayVideoError.unsupportedEncoder("Could not add source audio input.") }
                writer.add(input)
                streams.append(CompositedAudioStream(reader: reader, output: output, input: input, pendingSample: firstSample))
            }
            prepared = true
            return streams
        } catch OverlayVideoError.cancelled {
            throw OverlayVideoError.cancelled
        } catch {
            diagnoseFailure(stage: .readAudio, error: error)
            throw AudioExportFailure(underlying: error)
        }
    }

    private func muxOriginalAudio(videoURL: URL, outputURL: URL) throws {
        guard let sourceAsset else {
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
            return
        }
        let audioTracks = sourceAsset.tracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
            return
        }
        let duration = TransparentVideoFrameTiming(
            framesPerSecond: config.framesPerSecond,
            duration: config.duration
        ).outputDuration
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        let composition = try makeMuxComposition(
            videoURL: videoURL,
            duration: duration,
            excludingAudioRanges: []
        )

        do {
            diagnose(stage: .audioMuxPassthrough, phase: .begin)
            try exportComposition(
                composition,
                outputURL: outputURL,
                timeRange: timeRange,
                presetName: AVAssetExportPresetPassthrough,
                diagnosticStage: .audioMuxPassthrough
            )
        } catch OverlayVideoError.cancelled {
            throw OverlayVideoError.cancelled
        } catch {
            diagnoseFailure(stage: .audioMuxPassthrough, error: error)
            removePartialOutput(at: outputURL)
            diagnose(stage: .audioMuxReencode, phase: .begin)
            do {
                try exportComposition(
                    composition,
                    outputURL: outputURL,
                    timeRange: timeRange,
                    presetName: AVAssetExportPresetHighestQuality,
                    diagnosticStage: .audioMuxReencode
                )
            } catch OverlayVideoError.cancelled {
                throw OverlayVideoError.cancelled
            } catch {
                let skippedRanges = skippedVideoRangesSnapshot()
                guard !skippedRanges.isEmpty else { throw error }
                diagnoseFailure(stage: .audioMuxReencode, error: error)
                removePartialOutput(at: outputURL)
                let silenceComposition = try makeMuxComposition(
                    videoURL: videoURL,
                    duration: duration,
                    excludingAudioRanges: skippedRanges
                )
                try exportComposition(
                    silenceComposition,
                    outputURL: outputURL,
                    timeRange: timeRange,
                    presetName: AVAssetExportPresetHighestQuality,
                    diagnosticStage: .audioMuxReencode
                )
                recordAudioSilenceWarnings()
            }
        }
    }

    private func makeMuxComposition(
        videoURL: URL,
        duration: CMTime,
        excludingAudioRanges: [CMTimeRange]
    ) throws -> AVMutableComposition {
        guard sourceAsset != nil else {
            throw OverlayVideoError.writerFailed("Could not find the source asset before audio muxing.")
        }
        let videoAsset = AVURLAsset(url: videoURL)
        guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
            throw OverlayVideoError.writerFailed("Could not find rendered video track before audio muxing.")
        }

        let timeRange = CMTimeRange(start: .zero, duration: duration)
        let composition = try makeAudioComposition(duration: duration, excludingAudioRanges: excludingAudioRanges)
        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw OverlayVideoError.writerFailed("Could not create muxed video track.")
        }
        try compositionVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        return composition
    }

    private func makeAudioComposition(duration: CMTime, excludingAudioRanges: [CMTimeRange]) throws -> AVMutableComposition {
        guard let sourceAsset else { return AVMutableComposition() }
        let sourceAudioRange = CMTimeRange(
            start: CMTime(seconds: config.startTime, preferredTimescale: duration.timescale), duration: duration
        )
        let composition = AVMutableComposition()

        for audioTrack in sourceAsset.tracks(withMediaType: .audio) {
            let clippedRange = CMTimeRangeGetIntersection(audioTrack.timeRange, otherRange: sourceAudioRange)
            let audibleRanges = subtract(excludingAudioRanges, from: clippedRange)
            guard !audibleRanges.isEmpty else { continue }
            guard let compositionAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            for audibleRange in audibleRanges {
                let destinationStart = CMTimeSubtract(audibleRange.start, sourceAudioRange.start)
                try compositionAudio.insertTimeRange(audibleRange, of: audioTrack, at: destinationStart)
            }
        }
        return composition
    }

    private func subtract(_ excludedRanges: [CMTimeRange], from sourceRange: CMTimeRange) -> [CMTimeRange] {
        guard sourceRange.duration > .zero else { return [] }
        let exclusions = excludedRanges
            .map { CMTimeRangeGetIntersection($0, otherRange: sourceRange) }
            .filter { $0.duration > .zero }
            .sorted { CMTimeCompare($0.start, $1.start) < 0 }
        guard !exclusions.isEmpty else { return [sourceRange] }

        var result: [CMTimeRange] = []
        var cursor = sourceRange.start
        let sourceEnd = CMTimeRangeGetEnd(sourceRange)
        for exclusion in exclusions {
            if CMTimeCompare(exclusion.start, cursor) > 0 {
                result.append(CMTimeRange(start: cursor, duration: CMTimeSubtract(exclusion.start, cursor)))
            }
            cursor = maxTime(cursor, CMTimeRangeGetEnd(exclusion))
            if CMTimeCompare(cursor, sourceEnd) >= 0 { break }
        }
        if CMTimeCompare(cursor, sourceEnd) < 0 {
            result.append(CMTimeRange(start: cursor, duration: CMTimeSubtract(sourceEnd, cursor)))
        }
        return result
    }

    private func recordAudioSilenceWarnings() {
        for warning in currentExportResult().warnings where warning.kind == .videoSegmentSkipped {
            recordExportWarning(VideoExportWarning(
                kind: .skippedSegmentAudioSilenced,
                clipID: warning.clipID,
                sourceDisplayName: warning.sourceDisplayName,
                timelineStart: warning.timelineStart,
                duration: warning.duration
            ))
        }
    }

    private func exportComposition(
        _ composition: AVComposition,
        outputURL: URL,
        timeRange: CMTimeRange,
        presetName: String,
        diagnosticStage: VideoExportDiagnosticEvent.Stage
    ) throws {
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw OverlayVideoError.writerFailed("Could not create audio mux export session.")
        }
        removePartialOutput(at: outputURL)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = timeRange
        diagnose(stage: diagnosticStage, phase: .update, exportSession: exportSession)
        var lastReportedProgress = exportSession.progress

        try VideoExportSupport.waitForExport(
            exportSession,
            cancellationHandler: config.cancellationHandler,
            progressHandler: { [weak self, weak exportSession] in
                guard let self, let exportSession else { return }
                guard exportSession.progress > lastReportedProgress else { return }
                lastReportedProgress = exportSession.progress
                self.diagnose(stage: diagnosticStage, phase: .update, exportSession: exportSession)
            }
        )

        guard exportSession.status == .completed else {
            throw OverlayVideoError.writerFailed(describe(error: exportSession.error, fallback: "Audio muxing failed."), underlying: exportSession.error)
        }
        diagnose(stage: diagnosticStage, phase: .end, exportSession: exportSession)
    }

    private func hasAudioTrack(in asset: AVAsset) -> Bool {
        !asset.tracks(withMediaType: .audio).isEmpty
    }

    private func videoOutputSettings(
        width: Int,
        height: Int,
        codec: OverlayVideoCodec,
        averageBitRate: Int,
        encoderFrameRate: Int,
        expectedSourceFrameRate: Double,
        hardwareProfile: OverlayHardwareProfile
    ) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: codec.avCodecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        if let encoderSpecification = TransparentVideoWriter.hardwareEncoderSpecification(
            codec: codec,
            hardwareProfile: hardwareProfile,
            softwareOnly: config.softwareEncoding
        ) {
            #if os(macOS)
            settings[AVVideoEncoderSpecificationKey] = encoderSpecification
            #endif
        }
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: averageBitRate,
            AVVideoExpectedSourceFrameRateKey: expectedSourceFrameRate,
            AVVideoMaxKeyFrameIntervalKey: encoderFrameRate,
            AVVideoAllowFrameReorderingKey: false,
            kVTCompressionPropertyKey_RealTime as String: true
        ]
        // 软件编码器（如 iOS 模拟器）不接受该加速提示属性，传入会让 AVAssetWriterInput 直接抛异常。
        if !config.softwareEncoding && hardwareProfile.canUseHardwareEncoder(for: codec) {
            compressionProperties[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = true
        }
        settings[AVVideoCompressionPropertiesKey] = compressionProperties
        settings[AVVideoColorPropertiesKey] = VideoColorPipeline.outputColorProperties
        return settings
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

    private func makeTemporaryOutputURL(tag: String) -> URL {
        TransparentVideoWriter.makeTemporaryOutputURL(
            for: outputURL,
            tag: tag,
            fallbackBaseName: "datalayer-video",
            directory: config.temporaryDirectory
        )
    }

    private func removePartialOutput(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }

    private func maxTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) >= 0 ? lhs : rhs
    }

    private func describe(error: Error?, codec: OverlayVideoCodec) -> String {
        "\(describe(error: error, fallback: "Unknown writer failure")) while using \(codec.displayName)."
    }

    private func describe(error: Error?, fallback: String) -> String {
        guard let error else {
            return fallback
        }
        let nsError = error as NSError
        if nsError.userInfo.isEmpty {
            return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        }
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription) \(nsError.userInfo)"
    }

    private func diagnose(
        stage: VideoExportDiagnosticEvent.Stage,
        phase: VideoExportDiagnosticEvent.Phase,
        frameIndex: Int? = nil,
        totalFrames: Int? = nil,
        reader: AVAssetReader? = nil,
        writer: AVAssetWriter? = nil,
        exportSession: AVAssetExportSession? = nil,
        inputReady: Bool? = nil,
        source: SourceMetadata? = nil,
        preparationStep: VideoExportDiagnosticEvent.PreparationStep? = nil
    ) {
        deliverDiagnostic(diagnosticEvent(
            stage: stage,
            phase: phase,
            frameIndex: frameIndex,
            totalFrames: totalFrames,
            reader: reader,
            writer: writer,
            exportSession: exportSession,
            inputReady: inputReady,
            source: source,
            preparationStep: preparationStep
        ))
    }

    private func diagnosticEvent(
        stage: VideoExportDiagnosticEvent.Stage,
        phase: VideoExportDiagnosticEvent.Phase,
        frameIndex: Int? = nil,
        totalFrames: Int? = nil,
        reader: AVAssetReader? = nil,
        writer: AVAssetWriter? = nil,
        exportSession: AVAssetExportSession? = nil,
        inputReady: Bool? = nil,
        source: SourceMetadata? = nil,
        preparationStep: VideoExportDiagnosticEvent.PreparationStep? = nil
    ) -> VideoExportDiagnosticEvent {
        VideoExportDiagnosticEvent(
            stage: stage,
            phase: phase,
            frameIndex: frameIndex,
            totalFrames: totalFrames,
            readerStatus: reader.map(diagnosticReaderStatus),
            writerStatus: writer.map(diagnosticWriterStatus),
            exportStatus: exportSession.map(diagnosticExportStatus),
            exportProgress: exportSession.map { Double($0.progress) },
            inputReady: inputReady,
            sourceFourCC: source?.fourCC,
            sourceSize: source?.size,
            sourceFramesPerSecond: source?.framesPerSecond,
            sourceHasAudio: source?.hasAudio,
            preparationStep: preparationStep
        )
    }

    private func diagnoseFailure(stage: VideoExportDiagnosticEvent.Stage, error: Error) {
        let nsError = error as NSError
        deliverDiagnostic(VideoExportDiagnosticEvent(
            stage: stage,
            phase: .failure,
            errorDomain: nsError.domain,
            errorCode: nsError.code
        ))
    }

    private func deliverDiagnostic(_ event: VideoExportDiagnosticEvent) {
        diagnosticDeliveryLock.lock()
        config.diagnosticsHandler?(event)
        diagnosticDeliveryLock.unlock()
    }

    private func deliverLatestRenderDiagnostic(from tracker: RenderDiagnosticStageTracker) {
        diagnosticDeliveryLock.lock()
        if let event = tracker.takeLatest() {
            config.diagnosticsHandler?(event)
        }
        diagnosticDeliveryLock.unlock()
    }

    private struct SourceMetadata {
        let fourCC: UInt32?
        let size: VideoExportDiagnosticEvent.SourceSize?
        let framesPerSecond: Double?
        let hasAudio: Bool
    }

    private func sourceMetadata(for asset: AVAsset) -> SourceMetadata {
        let track = asset.tracks(withMediaType: .video).first
        let fourCC = track?.formatDescriptions.first.flatMap { description -> UInt32? in
            CMFormatDescriptionGetMediaSubType(description as! CMFormatDescription)
        }
        return SourceMetadata(
            fourCC: fourCC,
            size: track.map { VideoExportDiagnosticEvent.SourceSize(width: Int($0.naturalSize.width), height: Int($0.naturalSize.height)) },
            framesPerSecond: track.map { Double($0.nominalFrameRate) },
            hasAudio: hasAudioTrack(in: asset)
        )
    }

    private func diagnosticReaderStatus(_ reader: AVAssetReader) -> VideoExportDiagnosticEvent.ReaderStatus {
        switch reader.status {
        case .unknown: return .unknown
        case .reading: return .reading
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        @unknown default: return .unknown
        }
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

    private func diagnosticExportStatus(_ exportSession: AVAssetExportSession) -> VideoExportDiagnosticEvent.ExportStatus {
        switch exportSession.status {
        case .unknown: return .unknown
        case .waiting: return .waiting
        case .exporting: return .exporting
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        @unknown default: return .unknown
        }
    }
}

private struct AudioExportFailure: Error {
    let underlying: Error
}

private final class CompositedAudioStream {
    let reader: AVAssetReader
    let output: AVAssetReaderAudioMixOutput
    let input: AVAssetWriterInput
    var pendingSample: CMSampleBuffer?
    var finished = false

    init(reader: AVAssetReader, output: AVAssetReaderAudioMixOutput, input: AVAssetWriterInput, pendingSample: CMSampleBuffer) {
        self.reader = reader
        self.output = output
        self.input = input
        self.pendingSample = pendingSample
    }
}

extension VideoExportSupport {
    static func waitForRenderCompletion(
        _ finished: DispatchSemaphore,
        pollInterval: DispatchTimeInterval = .milliseconds(50),
        cancellationHandler: (() -> Bool)?,
        heartbeatInterval: TimeInterval = 1,
        heartbeatHandler: (() -> Void)? = nil,
        cancelProducer: () -> Void
    ) {
        var lastHeartbeat = ProcessInfo.processInfo.systemUptime
        var didRequestProducerCancellation = false
        while finished.wait(timeout: .now() + pollInterval) == .timedOut {
            let uptime = ProcessInfo.processInfo.systemUptime
            if uptime - lastHeartbeat >= heartbeatInterval {
                heartbeatHandler?()
                lastHeartbeat = uptime
            }
            guard cancellationHandler?() == true,
                  !didRequestProducerCancellation else { continue }
            didRequestProducerCancellation = true
            heartbeatHandler?()
            cancelProducer()
        }
    }
}

private final class RenderDiagnosticStageTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var reportedGeneration: UInt64 = 0
    private var event: VideoExportDiagnosticEvent?

    var currentStage: VideoExportDiagnosticEvent.Stage? {
        lock.lock()
        defer { lock.unlock() }
        return event?.stage
    }

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

    func markLatestReported() {
        lock.lock()
        reportedGeneration = generation
        lock.unlock()
    }
}
