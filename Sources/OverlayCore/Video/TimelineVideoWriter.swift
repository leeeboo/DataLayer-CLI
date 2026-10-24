#if canImport(AVFoundation)
import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation

#else
import Foundation
#endif

public struct TimelineVideoWriterConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case width, height, framesPerSecond, timelineStart, duration, averageBitRate, codec, activityTrim
        case softwareDecoding, softwareEncoding
    }
    public var width: Int
    public var height: Int
    public var framesPerSecond: Double
    public var timelineStart: TimeInterval
    public var duration: TimeInterval
    public var averageBitRate: Int
    public var codec: OverlayVideoCodec
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
        timelineStart: TimeInterval = 0,
        duration: TimeInterval,
        averageBitRate: Int = 12_000_000,
        codec: OverlayVideoCodec = .hevc,
        activityTrim: ActivityTrim = .none,
        progressHandler: ((Int, Int) -> Void)? = nil,
        cancellationHandler: (() -> Bool)? = nil,
        diagnosticsHandler: ((VideoExportDiagnosticEvent) -> Void)? = nil,
        temporaryDirectory: URL? = nil
    ) {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.timelineStart = timelineStart
        self.duration = duration
        self.averageBitRate = averageBitRate
        self.codec = codec
        self.activityTrim = activityTrim
        self.progressHandler = progressHandler
        self.cancellationHandler = cancellationHandler
        self.diagnosticsHandler = diagnosticsHandler
        self.temporaryDirectory = temporaryDirectory
    }
}

/// One resolved, visible video interval rendered directly from its original source during export.
/// The timeline composition remains the audio source; avoiding its video compositor prevents
/// incompatible source formats from stalling an `AVAssetReaderVideoCompositionOutput` at frame 0.
#if canImport(AVFoundation)
struct TimelineVideoSegment {
    let clipID: String
    let sourceDisplayName: String
    let asset: AVAsset
    let videoTrack: AVAssetTrack
    let timelineRange: CMTimeRange
    let sourceRange: CMTimeRange
    let sourceTransform: CGAffineTransform
    var sourceInfo: VideoColorInfo? = nil
    var colorSettings: VideoColorSettings? = nil
    var lut: ClipLUT? = nil
}

#endif

/// Resolves the visible overlay clip on each enabled overlay track without revisiting every clip
/// for every rendered frame. Tracks stay in project order; each cursor preserves the last clip in
/// its track array as the winner when legacy clips overlap.
final class TimelineOverlayTimeIndex {
    private var trackCursors: [TrackCursor]
    private(set) var processedEventCount = 0

    init(project: TimelineProject) {
        trackCursors = project.tracks
            .filter { $0.kind == .overlay && $0.isEnabled }
            .map(TrackCursor.init(track:))
    }

    func activeClipIDs(atTimelineTime timelineTime: TimeInterval) -> [String] {
        guard timelineTime.isFinite else { return [] }

        return trackCursors.compactMap { cursor in
            let result = cursor.activeClipID(atTimelineTime: timelineTime)
            processedEventCount += result.processedEventCount
            return result.clipID
        }
    }

    private final class TrackCursor {
        private struct Event {
            enum Kind: Int {
                case end
                case start
            }

            var time: TimeInterval
            var kind: Kind
            var clipIndex: Int
            var clipID: String
        }

        private struct ActiveClip {
            var index: Int
            var id: String
        }

        private var events: [Event]
        private var nextEventIndex = 0
        private var endedClipIndices = Set<Int>()
        private var activeClips = [ActiveClip]()
        private var lastTimelineTime = -TimeInterval.infinity

        init(track: TimelineTrack) {
            var events: [Event] = []
            events.reserveCapacity(track.clips.count * 2)

            for (clipIndex, clip) in track.clips.enumerated() where clip.isEnabled {
                let start = clip.timelineStart
                let end = clip.timelineEnd
                guard start.isFinite,
                      clip.duration > 0,
                      end > start else {
                    continue
                }

                events.append(Event(time: start, kind: .start, clipIndex: clipIndex, clipID: clip.id))
                if end.isFinite {
                    events.append(Event(time: end, kind: .end, clipIndex: clipIndex, clipID: clip.id))
                }
            }

            self.events = events.sorted {
                $0.time != $1.time ? $0.time < $1.time : $0.kind.rawValue < $1.kind.rawValue
            }
        }

        func activeClipID(atTimelineTime timelineTime: TimeInterval) -> (clipID: String?, processedEventCount: Int) {
            if timelineTime < lastTimelineTime {
                reset()
            }
            lastTimelineTime = timelineTime

            var processedEventCount = 0
            while nextEventIndex < events.count, events[nextEventIndex].time <= timelineTime {
                let event = events[nextEventIndex]
                nextEventIndex += 1
                processedEventCount += 1

                switch event.kind {
                case .end:
                    endedClipIndices.insert(event.clipIndex)
                case .start:
                    insert(ActiveClip(index: event.clipIndex, id: event.clipID))
                }
            }

            while let winner = activeClips.first, endedClipIndices.contains(winner.index) {
                removeHighestPriorityClip()
            }
            return (activeClips.first?.id, processedEventCount)
        }

        private func reset() {
            nextEventIndex = 0
            endedClipIndices.removeAll(keepingCapacity: true)
            activeClips.removeAll(keepingCapacity: true)
            lastTimelineTime = -TimeInterval.infinity
        }

        private func insert(_ clip: ActiveClip) {
            activeClips.append(clip)
            var index = activeClips.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard activeClips[parent].index < activeClips[index].index else { break }
                activeClips.swapAt(parent, index)
                index = parent
            }
        }

        private func removeHighestPriorityClip() {
            guard !activeClips.isEmpty else { return }
            let last = activeClips.removeLast()
            guard !activeClips.isEmpty else { return }
            activeClips[0] = last

            var index = 0
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var largest = index
                if left < activeClips.count, activeClips[left].index > activeClips[largest].index {
                    largest = left
                }
                if right < activeClips.count, activeClips[right].index > activeClips[largest].index {
                    largest = right
                }
                guard largest != index else { return }
                activeClips.swapAt(index, largest)
                index = largest
            }
        }
    }
}

#if canImport(AVFoundation)
public final class TimelineVideoWriter {
    private let outputURL: URL
    private let project: TimelineProject
    private let telemetrySeriesByAssetID: [String: TelemetrySeries]
    private let config: TimelineVideoWriterConfig
    private let diagnosticDeliveryLock = NSLock()
    private var didReportPreciseFailure = false

    public init(
        outputURL: URL,
        project: TimelineProject,
        telemetrySeriesByAssetID: [String: TelemetrySeries],
        config: TimelineVideoWriterConfig
    ) {
        self.outputURL = outputURL
        self.project = project
        self.telemetrySeriesByAssetID = telemetrySeriesByAssetID
        self.config = config
    }

    @discardableResult
    public func write() throws -> VideoExportResult {
        try VideoExportCleanup.check()
        #if os(macOS)
        if let executable = VideoExportWorker.executableURL {
            return try VideoExportWorker.write(outputURL: outputURL, project: project,
                                              telemetry: telemetrySeriesByAssetID, config: config,
                                              executableURL: executable)
        }
        return try VideoExportSupport.performWriting(
            cancellationHandler: config.cancellationHandler,
            progressHandler: config.progressHandler,
            diagnosticsHandler: config.diagnosticsHandler,
            securityScopedURLs: [outputURL] + project.assets.map(\.url)
        ) { control in
            var config = self.config
            config.cancellationHandler = { control.isCancelled }
            config.progressHandler = control.recordProgress
            config.diagnosticsHandler = control.recordDiagnostic
            return try TimelineVideoWriter(outputURL: self.outputURL, project: self.project,
                                          telemetrySeriesByAssetID: self.telemetrySeriesByAssetID,
                                          config: config).writeUnmonitored()
        }
        #else
        return try writeUnmonitored()
        #endif
    }

    func writeUnmonitored() throws -> VideoExportResult {
        resetDiagnosticFailure()
        do {
            diagnosePreparation(step: .validateProject, phase: .begin)
            if let issue = project.firstExportValidationIssue(
                mode: config.codec.exportMode,
                timelineStart: config.timelineStart,
                duration: config.duration,
                availableTelemetryAssetIDs: Set(telemetrySeriesByAssetID.keys)
            ) {
                diagnosePreparation(step: .validateProject, phase: .failure)
                throw OverlayVideoError.invalidConfiguration(issue.errorDescription)
            }
            diagnosePreparation(step: .validateProject, phase: .end)

            let result: VideoExportResult
            switch config.codec.exportMode {
            case .video:
                result = try writeCompositedVideo()
            case .overlay:
                try writeTransparentOverlay()
                result = .success
            }
            deliverDiagnostic(.init(stage: .exportCompleted, phase: .end))
            return result
        } catch {
            let nsError = error as NSError
            if !hasReportedPreciseFailure {
                deliverDiagnostic(.init(
                    stage: .exportFailed,
                    phase: .failure,
                    errorDomain: nsError.domain,
                    errorCode: nsError.code
                ))
            }
            throw error
        }
    }

    private func writeCompositedVideo() throws -> VideoExportResult {
        diagnosePreparation(step: .collectVideoClips, phase: .begin)
        let videoClips: [TimelineClip]
        do {
            videoClips = try project.validatedVideoClipsForExport(
                timelineStart: config.timelineStart,
                duration: config.duration
            )
        } catch {
            diagnosePreparation(step: .collectVideoClips, phase: .failure, error: error)
            throw error
        }
        diagnosePreparation(step: .collectVideoClips, phase: .end, sourceCount: videoClips.count)
        let video = try videoClips.isEmpty ? nil : makeCompositedVideoSource(videoClips)

        diagnosePreparation(step: .prepareOverlays, phase: .begin)
        let overlays: [OverlayComposition]
        do {
            overlays = try makeOverlayCompositions()
        } catch {
            diagnosePreparation(step: .prepareOverlays, phase: .failure, error: error)
            throw error
        }
        diagnosePreparation(step: .prepareOverlays, phase: .end)
        let overlaysByClipID = overlayCompositionsByClipID(overlays)
        let overlayTimeIndex = TimelineOverlayTimeIndex(project: project)

        diagnosePreparation(step: .prepareRenderResources, phase: .begin)
        let renderPool: CVPixelBufferPool
        do {
            renderPool = try TransparentVideoWriter.makePixelBufferPool(
                width: config.width,
                height: config.height,
                minimumBufferCount: overlays.count + 2
            )
        } catch {
            diagnosePreparation(step: .prepareRenderResources, phase: .failure, error: error)
            throw error
        }
        let hardwareProfile = OverlayHardwareProfile.current
        let compositeContext = OverlayCIContextFactory.makeContext(profile: hardwareProfile)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bounds = CGRect(x: 0, y: 0, width: config.width, height: config.height)
        diagnosePreparation(step: .prepareRenderResources, phase: .end)

        var writerConfig = CompositedVideoWriterConfig(
            width: config.width,
            height: config.height,
            framesPerSecond: config.framesPerSecond,
            startTime: video?.startTime ?? 0,
            duration: config.duration,
            averageBitRate: config.averageBitRate,
            codec: config.codec,
            activityTrim: config.activityTrim,
            progressHandler: config.progressHandler,
            cancellationHandler: config.cancellationHandler,
            diagnosticsHandler: deliverDiagnostic
        )
        writerConfig.temporaryDirectory = config.temporaryDirectory
        writerConfig.softwareDecoding = config.softwareDecoding
        writerConfig.softwareEncoding = config.softwareEncoding
        let renderOverlay: (TimeInterval, CVPixelBuffer) throws -> Void = { timelineTime, overlayBuffer in
            let activeOverlays = self.activeOverlayCompositions(
                atTimelineTime: timelineTime,
                compositionsByClipID: overlaysByClipID,
                timeIndex: overlayTimeIndex
            )
            let renderedBuffer = try self.renderTransparentFrame(
                activeOverlays,
                timelineTime: timelineTime,
                renderPool: renderPool,
                compositeContext: compositeContext,
                colorSpace: colorSpace
            )
            compositeContext.render(
                CIImage(cvPixelBuffer: renderedBuffer),
                to: overlayBuffer,
                bounds: bounds,
                colorSpace: colorSpace
            )
        }

        diagnosePreparation(step: .createCompositedWriter, phase: .begin)
        let writer: CompositedVideoWriter
        if let video {
            writer = CompositedVideoWriter(
                outputURL: outputURL,
                sourceAsset: video.asset,
                sourceDescription: video.description,
                sourceVideoSegments: video.segments,
                config: writerConfig,
                overlayStartTime: config.timelineStart,
                renderOverlay: renderOverlay,
                initialWarnings: video.warnings
            )
        } else {
            writer = CompositedVideoWriter(
                outputURL: outputURL,
                config: writerConfig,
                overlayStartTime: config.timelineStart,
                renderOverlay: renderOverlay
            )
        }
        diagnosePreparation(step: .createCompositedWriter, phase: .end)
        return try writer.writeUnmonitored()
    }

    private func writeTransparentOverlay() throws {
        diagnosePreparation(step: .prepareOverlays, phase: .begin)
        let overlays: [OverlayComposition]
        do {
            overlays = try makeOverlayCompositions()
        } catch {
            diagnosePreparation(step: .prepareOverlays, phase: .failure, error: error)
            throw error
        }
        diagnosePreparation(step: .prepareOverlays, phase: .end, sourceCount: overlays.count)
        if overlays.count != 1 || !clipCoversExportRange(overlays[0].clip) {
            try writeMultiTransparentOverlay(overlays)
            return
        }

        let overlay = overlays[0]
        let activityOffsetFromTimeline = overlay.clip.sourceIn - overlay.clip.timelineStart

        try TransparentVideoWriter(
            outputURL: outputURL,
            series: overlay.series,
            config: TransparentVideoWriterConfig(
                width: config.width,
                height: config.height,
                framesPerSecond: config.framesPerSecond,
                startTime: config.timelineStart,
                duration: config.duration,
                averageBitRate: config.averageBitRate,
                timeSync: TelemetryTimeSync(videoSyncTime: 0, fitSyncTime: activityOffsetFromTimeline),
                activityOffsetMilliseconds: project.asset(id: overlay.clip.assetID)?.activityOffsetMilliseconds,
                fitClockOffsetMilliseconds: project.asset(id: overlay.clip.assetID)?.fitClockOffsetMilliseconds,
                codec: config.codec,
                overlayLayout: overlay.clip.layout ?? .default,
                distanceUnit: overlay.clip.distanceUnit ?? project.distanceUnit,
                timeZone: project.displayTimeZone(for: project.asset(id: overlay.clip.assetID)),
                activityTrim: config.activityTrim,
                progressHandler: config.progressHandler,
                cancellationHandler: config.cancellationHandler,
                diagnosticsHandler: deliverDiagnostic,
                temporaryDirectory: config.temporaryDirectory
            )
        ).writeUnmonitored()
    }

    private func writeMultiTransparentOverlay(_ overlays: [OverlayComposition]) throws {
        var activeStage: VideoExportDiagnosticEvent.Stage = .prepareWriter
        var writer: AVAssetWriter?
        let temporaryOutputURL = makeTemporaryOutputURL(tag: "timeline-overlay")
        TransparentVideoWriter.removeStaleTemporaryOutputs()
        removePartialOutput(at: temporaryOutputURL)

        do {
            try validateTransparentConfiguration()
            let overlaysByClipID = overlayCompositionsByClipID(overlays)
            let overlayTimeIndex = TimelineOverlayTimeIndex(project: project)
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
            let frameCount = timing.frameCount
            let fps = timing.framesPerSecond
            let encoderFrameRate = try encoderFrameRateValue(fps)
            let hardwareProfile = OverlayHardwareProfile.current
            diagnose(stage: .prepareWriter, phase: .begin, totalFrames: frameCount)

            let outputWriter = try AVAssetWriter(outputURL: temporaryOutputURL, fileType: .mov)
            writer = outputWriter
            outputWriter.movieTimeScale = timing.mediaTimeScale
            let settings = TransparentVideoWriter.videoOutputSettings(
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
            guard outputWriter.canAdd(input) else {
                throw OverlayVideoError.unsupportedEncoder(
                    "This macOS installation cannot add a \(config.codec.displayName) video writer input."
                )
            }
            outputWriter.add(input)

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: OverlayPixelBufferAttributes.canvas(width: width, height: height)
            )
            guard outputWriter.startWriting() else {
                throw OverlayVideoError.cannotStartWriter(
                    describe(error: outputWriter.error, codec: config.codec),
                    underlying: outputWriter.error
                )
            }
            outputWriter.startSession(atSourceTime: .zero)
            diagnose(stage: .prepareWriter, phase: .end, totalFrames: frameCount, writer: outputWriter)

            let renderQueue = DispatchQueue(label: "run.libo.overlay.timeline-video-writer")
            let renderFinished = DispatchSemaphore(value: 0)
            let renderPool = try TransparentVideoWriter.makePixelBufferPool(
                width: width,
                height: height,
                minimumBufferCount: overlays.count + 2
            )
            let alphaContext = config.codec == .hevcAlpha
                ? OverlayCIContextFactory.makeContext(profile: hardwareProfile)
                : nil
            let compositeContext = OverlayCIContextFactory.makeContext(profile: hardwareProfile)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var frameIndex = 0
            var renderError: Error?
            var didFinishInput = false
            let renderDiagnosticTracker = config.diagnosticsHandler.map { _ in TimelineRenderDiagnosticStageTracker() }
            let reportLatestRenderDiagnostic: () -> Void = {
                guard let renderDiagnosticTracker else { return }
                self.deliverLatestRenderDiagnostic(from: renderDiagnosticTracker)
            }

            activeStage = .awaitReady
            diagnose(stage: .awaitReady, phase: .begin, totalFrames: frameCount, writer: outputWriter)
            input.requestMediaDataWhenReady(on: renderQueue) {
                renderDiagnosticTracker?.update(self.diagnosticEvent(
                    stage: .awaitReady,
                    phase: .update,
                    frameIndex: frameIndex,
                    totalFrames: frameCount,
                    writer: outputWriter,
                    inputReady: input.isReadyForMoreMediaData
                ))
                while input.isReadyForMoreMediaData, frameIndex < frameCount, renderError == nil {
                    var frameStage: VideoExportDiagnosticEvent.Stage = .renderOverlay
                    do {
                        try autoreleasepool {
                            if self.config.cancellationHandler?() == true {
                                throw OverlayVideoError.cancelled
                            }

                            guard let appendPool = adaptor.pixelBufferPool else {
                                throw OverlayVideoError.cannotCreatePixelBuffer
                            }
                            let presentationTime = timing.presentationTime(for: frameIndex)
                            let timelineTime = self.config.timelineStart + CMTimeGetSeconds(presentationTime)
                            let activeOverlays = self.activeOverlayCompositions(
                                atTimelineTime: timelineTime,
                                compositionsByClipID: overlaysByClipID,
                                timeIndex: overlayTimeIndex
                            )
                            let renderedBuffer = try self.renderTransparentFrame(
                                activeOverlays,
                                timelineTime: timelineTime,
                                renderPool: renderPool,
                                compositeContext: compositeContext,
                                colorSpace: colorSpace,
                                diagnosticHandler: { stage in
                                    frameStage = stage
                                    renderDiagnosticTracker?.update(self.diagnosticEvent(
                                        stage: stage,
                                        phase: .begin,
                                        frameIndex: frameIndex,
                                        totalFrames: frameCount,
                                        writer: outputWriter
                                    ))
                                }
                            )

                            let appendBuffer: CVPixelBuffer
                            if let alphaContext {
                                appendBuffer = try TransparentVideoWriter.makePixelBuffer(from: appendPool)
                                frameStage = .ciComposite
                                renderDiagnosticTracker?.update(self.diagnosticEvent(
                                    stage: .ciComposite,
                                    phase: .begin,
                                    frameIndex: frameIndex,
                                    totalFrames: frameCount,
                                    writer: outputWriter
                                ))
                                TransparentVideoWriter.prepareHEVCAlphaForEncoding(
                                    from: renderedBuffer,
                                    to: appendBuffer,
                                    context: alphaContext,
                                    colorSpace: colorSpace
                                )
                            } else {
                                appendBuffer = renderedBuffer
                                TransparentVideoWriter.preparePremultipliedAlphaForEncoding(on: appendBuffer)
                            }

                            frameStage = .appendFrame
                            renderDiagnosticTracker?.update(self.diagnosticEvent(
                                stage: .appendFrame,
                                phase: .begin,
                                frameIndex: frameIndex,
                                totalFrames: frameCount,
                                writer: outputWriter,
                                inputReady: input.isReadyForMoreMediaData
                            ))
                            guard try TransparentVideoWriter.appendPixelBuffer(
                                appendBuffer,
                                to: input,
                                at: presentationTime,
                                duration: timing.frameDuration
                            ) else {
                                throw OverlayVideoError.writerFailed(
                                    self.describe(error: outputWriter.error, codec: self.config.codec),
                                    underlying: outputWriter.error
                                )
                            }

                            frameIndex += 1
                            if frameIndex == frameCount || frameIndex % Int(max(1, fps)) == 0 {
                                self.config.progressHandler?(frameIndex, frameCount)
                            }
                        }
                    } catch {
                        self.diagnoseFailure(
                            stage: frameStage,
                            error: error,
                            frameIndex: frameIndex,
                            totalFrames: frameCount,
                            writer: outputWriter,
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
                        writer: outputWriter,
                        inputReady: input.isReadyForMoreMediaData
                    ))
                }
                if (frameIndex >= frameCount || renderError != nil), !didFinishInput {
                    didFinishInput = true
                    self.deliverLatestRenderDiagnostic(from: renderDiagnosticTracker)
                    self.diagnose(stage: .finishInput, phase: .begin, frameIndex: frameIndex, totalFrames: frameCount, writer: outputWriter)
                    if renderError == nil {
                        outputWriter.endSession(atSourceTime: timing.outputDuration)
                    }
                    input.markAsFinished()
                    self.diagnose(stage: .finishInput, phase: .end, frameIndex: frameIndex, totalFrames: frameCount, writer: outputWriter)
                    renderFinished.signal()
                }
            }
            VideoExportSupport.waitForRenderCompletion(
                renderFinished,
                cancellationHandler: config.cancellationHandler,
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
            diagnose(stage: .awaitReady, phase: .end, frameIndex: frameIndex, totalFrames: frameCount, writer: outputWriter)

            if let renderError {
                outputWriter.cancelWriting()
                if !hasReportedPreciseFailure {
                    diagnoseFailure(
                        stage: .awaitReady,
                        error: renderError,
                        frameIndex: frameIndex,
                        totalFrames: frameCount,
                        writer: outputWriter
                    )
                }
                throw renderError
            }

            activeStage = .finishWriter
            diagnose(stage: .finishWriter, phase: .begin, writer: outputWriter)
            do {
                try VideoExportSupport.finishWriting(
                    outputWriter,
                    cancellationHandler: config.cancellationHandler
                )
            } catch {
                diagnoseFailure(stage: .finishWriter, error: error, writer: outputWriter)
                throw error
            }
            diagnose(stage: .finishWriter, phase: .end, writer: outputWriter)

            guard outputWriter.status == .completed else {
                let error = OverlayVideoError.writerFailed(
                    describe(error: outputWriter.error, codec: config.codec),
                    underlying: outputWriter.error
                )
                diagnoseFailure(stage: .finishWriter, error: error, writer: outputWriter)
                throw error
            }

            activeStage = .installOutput
            diagnose(stage: .installOutput, phase: .begin)
            do {
                try VideoExportSupport.installCompletedOutput(
                    from: temporaryOutputURL,
                    to: outputURL,
                    cancellationHandler: config.cancellationHandler,
                    diagnosticsHandler: config.diagnosticsHandler == nil ? nil : deliverDiagnostic
                )
            } catch {
                if !hasReportedPreciseFailure {
                    diagnoseFailure(stage: .installOutput, error: error, writer: outputWriter)
                }
                throw error
            }
            diagnose(stage: .installOutput, phase: .end)
        } catch {
            removePartialOutput(at: temporaryOutputURL)
            if !hasReportedPreciseFailure {
                diagnoseFailure(stage: activeStage, error: error, writer: writer)
            }
            throw error
        }
    }

    private func renderTransparentFrame(
        _ overlays: [OverlayComposition],
        timelineTime: TimeInterval,
        renderPool: CVPixelBufferPool,
        compositeContext: CIContext,
        colorSpace: CGColorSpace,
        diagnosticHandler: ((VideoExportDiagnosticEvent.Stage) -> Void)? = nil
    ) throws -> CVPixelBuffer {
        var accumulated = try TransparentVideoWriter.makePixelBuffer(from: renderPool)
        clearPixelBuffer(accumulated)

        for overlay in overlays {
            let layerBuffer = try TransparentVideoWriter.makePixelBuffer(from: renderPool)
            diagnosticHandler?(.renderOverlay)
            try overlay.renderer.render(videoTime: timelineTime, into: layerBuffer)

            let composed = try TransparentVideoWriter.makePixelBuffer(from: renderPool)
            clearPixelBuffer(composed)
            let image = CIImage(cvPixelBuffer: layerBuffer)
                .composited(over: CIImage(cvPixelBuffer: accumulated))
            diagnosticHandler?(.ciComposite)
            compositeContext.render(
                image,
                to: composed,
                bounds: CGRect(x: 0, y: 0, width: config.width, height: config.height),
                colorSpace: colorSpace
            )
            accumulated = composed
        }

        return accumulated
    }

    private func overlayCompositionsByClipID(
        _ overlays: [OverlayComposition]
    ) -> [String: OverlayComposition] {
        overlays.reduce(into: [:]) { result, composition in
            result[composition.clip.id] = composition
        }
    }

    private func activeOverlayCompositions(
        atTimelineTime timelineTime: TimeInterval,
        compositionsByClipID: [String: OverlayComposition],
        timeIndex: TimelineOverlayTimeIndex
    ) -> [OverlayComposition] {
        timeIndex.activeClipIDs(atTimelineTime: timelineTime).compactMap {
            compositionsByClipID[$0]
        }
    }

    private func clipCoversExportRange(_ clip: TimelineClip) -> Bool {
        let epsilon = 1e-6
        return clip.timelineStart <= config.timelineStart + epsilon
            && clip.timelineEnd >= config.timelineStart + config.duration - epsilon
    }

    private func makeCompositedVideoSource(
        _ videoClips: [TimelineClip]
    ) throws -> (
        asset: AVAsset,
        description: String,
        startTime: TimeInterval,
        segments: [TimelineVideoSegment],
        warnings: [VideoExportWarning]
    ) {
        diagnosePreparation(step: .prepareVideoSegments, phase: .begin, sourceCount: videoClips.count)
        let preparedSegments: (segments: [TimelineVideoSegment], warnings: [VideoExportWarning])
        do {
            preparedSegments = try makeTimelineVideoSegments(videoClips)
        } catch {
            diagnosePreparation(step: .prepareVideoSegments, phase: .failure, sourceCount: videoClips.count, error: error)
            throw error
        }
        diagnosePreparation(step: .prepareVideoSegments, phase: .end, sourceCount: videoClips.count)

        diagnosePreparation(step: .prepareAudioComposition, phase: .begin, sourceCount: videoClips.count)
        let audioComposition: AVMutableComposition
        do {
            audioComposition = try makeTimelineAudioComposition(videoClips)
        } catch {
            diagnosePreparation(step: .prepareAudioComposition, phase: .failure, sourceCount: videoClips.count, error: error)
            throw error
        }
        diagnosePreparation(step: .prepareAudioComposition, phase: .end, sourceCount: videoClips.count)
        return (
            audioComposition,
            "timeline audio composition",
            config.timelineStart,
            preparedSegments.segments,
            preparedSegments.warnings
        )
    }

    private func makeTimelineVideoSegments(
        _ videoClips: [TimelineClip]
    ) throws -> (segments: [TimelineVideoSegment], warnings: [VideoExportWarning]) {
        let timescale: CMTimeScale = 60_000
        let renderSize = CGSize(width: config.width, height: config.height)
        var segments: [TimelineVideoSegment] = []
        var warnings: [VideoExportWarning] = []

        for (offset, clip) in videoClips.enumerated() {
            try VideoExportSupport.throwIfCancelled(config.cancellationHandler)
            guard let videoAsset = project.asset(id: clip.assetID), videoAsset.kind == .video else {
                throw OverlayVideoError.invalidConfiguration("Timeline video clip references a missing video asset.")
            }
            let sourceIndex = offset + 1
            let sourceCount = videoClips.count
            diagnosePreparation(
                step: .inspectVideoSource,
                phase: .begin,
                sourceIndex: sourceIndex,
                sourceCount: sourceCount,
                clip: clip
            )
            let sourceFileSizeBytes = diagnosticFileSize(at: videoAsset.url)
            let asset = AVURLAsset(url: videoAsset.url)
            let videoTracks = asset.tracks(withMediaType: .video)
            diagnosePreparation(
                step: .inspectVideoSource,
                phase: .end,
                sourceIndex: sourceIndex,
                sourceCount: sourceCount,
                sourceFileSizeBytes: sourceFileSizeBytes,
                sourceVideoTrackCount: videoTracks.count,
                clip: clip
            )
            guard let videoTrack = videoTracks.first else {
                warnings.append(skippedVideoWarning(for: clip, asset: videoAsset))
                continue
            }

            let sourceRange: CMTimeRange
            diagnosePreparation(
                step: .resolveVideoRange,
                phase: .begin,
                sourceIndex: sourceIndex,
                sourceCount: sourceCount,
                sourceFileSizeBytes: sourceFileSizeBytes,
                sourceVideoTrackCount: videoTracks.count,
                clip: clip
            )
            do {
                sourceRange = try TimelineVideoCompositionBuilder.availableVideoSourceRange(
                    for: clip,
                    videoTrack: videoTrack,
                    preferredTimescale: timescale
                )
            } catch {
                diagnosePreparation(
                    step: .resolveVideoRange,
                    phase: .failure,
                    sourceIndex: sourceIndex,
                    sourceCount: sourceCount,
                    sourceFileSizeBytes: sourceFileSizeBytes,
                    sourceVideoTrackCount: videoTracks.count,
                    clip: clip,
                    error: error
                )
                warnings.append(skippedVideoWarning(for: clip, asset: videoAsset))
                continue
            }
            diagnosePreparation(
                step: .resolveVideoRange,
                phase: .end,
                sourceIndex: sourceIndex,
                sourceCount: sourceCount,
                sourceFileSizeBytes: sourceFileSizeBytes,
                sourceVideoTrackCount: videoTracks.count,
                clip: clip
            )

            diagnosePreparation(
                step: .resolveVideoTransform,
                phase: .begin,
                sourceIndex: sourceIndex,
                sourceCount: sourceCount,
                sourceFileSizeBytes: sourceFileSizeBytes,
                sourceVideoTrackCount: videoTracks.count,
                clip: clip
            )
            let sourceSize = videoTrack.naturalSize
            let sourceFramesPerSecond = Double(videoTrack.nominalFrameRate)
            let sourceTransform = TimelineVideoCompositionBuilder.aspectFitTransform(
                naturalSize: sourceSize,
                preferredTransform: videoTrack.preferredTransform,
                renderSize: renderSize
            )
            diagnosePreparation(
                step: .resolveVideoTransform,
                phase: .end,
                sourceIndex: sourceIndex,
                sourceCount: sourceCount,
                sourceFileSizeBytes: sourceFileSizeBytes,
                sourceVideoTrackCount: videoTracks.count,
                sourceSize: .init(width: Int(sourceSize.width), height: Int(sourceSize.height)),
                sourceFramesPerSecond: sourceFramesPerSecond,
                clip: clip
            )

            segments.append(TimelineVideoSegment(
                clipID: clip.id,
                sourceDisplayName: videoAsset.displayName,
                asset: asset,
                videoTrack: videoTrack,
                timelineRange: CMTimeRange(
                    start: CMTime(seconds: clip.timelineStart, preferredTimescale: timescale),
                    duration: sourceRange.duration
                ),
                sourceRange: sourceRange,
                sourceTransform: sourceTransform,
                sourceInfo: videoAsset.colorInfo
                    ?? (videoTrack.formatDescriptions as? [CMFormatDescription])?.first
                        .flatMap { VideoColorInfo.read(from: $0) },
                colorSettings: clip.colorSettings,
                lut: clip.lut
            ))
        }
        return (segments, warnings)
    }

    private func makeTimelineAudioComposition(_ videoClips: [TimelineClip]) throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let timescale = FrameRateCanonicalizer.timelineTimescale

        for (offset, clip) in videoClips.enumerated() {
            try VideoExportSupport.throwIfCancelled(config.cancellationHandler)
            guard let videoAsset = project.asset(id: clip.assetID), videoAsset.kind == .video else {
                throw OverlayVideoError.invalidConfiguration("Timeline video clip references a missing video asset.")
            }
            let sourceIndex = offset + 1
            let sourceCount = videoClips.count
            diagnosePreparation(
                step: .inspectAudioSource,
                phase: .begin,
                sourceIndex: sourceIndex,
                sourceCount: sourceCount,
                clip: clip
            )
            let sourceFileSizeBytes = diagnosticFileSize(at: videoAsset.url)
            let sourceAsset = AVURLAsset(url: videoAsset.url)
            let requestedDuration = CMTime(seconds: clip.duration, preferredTimescale: timescale)
            let destinationStart = CMTime(seconds: clip.timelineStart, preferredTimescale: timescale)
            let sourceAudioTracks = sourceAsset.tracks(withMediaType: .audio)
            diagnosePreparation(
                step: .inspectAudioSource,
                phase: .end,
                sourceIndex: sourceIndex,
                sourceCount: sourceCount,
                sourceFileSizeBytes: sourceFileSizeBytes,
                sourceAudioTrackCount: sourceAudioTracks.count,
                clip: clip
            )

            for (trackOffset, sourceAudioTrack) in sourceAudioTracks.enumerated() {
                diagnosePreparation(
                    step: .insertAudioTrack,
                    phase: .begin,
                    sourceIndex: sourceIndex,
                    sourceCount: sourceCount,
                    sourceFileSizeBytes: sourceFileSizeBytes,
                    sourceAudioTrackCount: sourceAudioTracks.count,
                    mediaTrackIndex: trackOffset + 1,
                    mediaTrackCount: sourceAudioTracks.count,
                    clip: clip
                )
                let audioStart = CMTimeAdd(
                    sourceAudioTrack.timeRange.start,
                    CMTime(seconds: clip.sourceIn, preferredTimescale: timescale)
                )
                let availableDuration = CMTimeSubtract(CMTimeRangeGetEnd(sourceAudioTrack.timeRange), audioStart)
                let audioDuration = minTime(requestedDuration, availableDuration)
                guard audioStart >= sourceAudioTrack.timeRange.start,
                      audioDuration > .zero else {
                    diagnosePreparation(
                        step: .insertAudioTrack,
                        phase: .end,
                        sourceIndex: sourceIndex,
                        sourceCount: sourceCount,
                        sourceFileSizeBytes: sourceFileSizeBytes,
                        sourceAudioTrackCount: sourceAudioTracks.count,
                        mediaTrackIndex: trackOffset + 1,
                        mediaTrackCount: sourceAudioTracks.count,
                        clip: clip
                    )
                    continue
                }
                let destinationRange = CMTimeRange(start: destinationStart, duration: audioDuration)
                let reusableTrack = composition.mutableTrack(compatibleWith: sourceAudioTrack).flatMap { track in
                    audioTrack(track, hasSegmentOverlapping: destinationRange) ? nil : track
                }
                let createdTrack = reusableTrack == nil
                    ? composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                    : nil
                guard let compositionAudioTrack = reusableTrack ?? createdTrack else {
                    diagnosePreparation(
                        step: .insertAudioTrack,
                        phase: .end,
                        sourceIndex: sourceIndex,
                        sourceCount: sourceCount,
                        sourceFileSizeBytes: sourceFileSizeBytes,
                        sourceAudioTrackCount: sourceAudioTracks.count,
                        mediaTrackIndex: trackOffset + 1,
                        mediaTrackCount: sourceAudioTracks.count,
                        clip: clip
                    )
                    continue
                }
                do {
                    try compositionAudioTrack.insertTimeRange(
                        CMTimeRange(start: audioStart, duration: audioDuration),
                        of: sourceAudioTrack,
                        at: destinationStart
                    )
                    diagnosePreparation(
                        step: .insertAudioTrack,
                        phase: .end,
                        sourceIndex: sourceIndex,
                        sourceCount: sourceCount,
                        sourceFileSizeBytes: sourceFileSizeBytes,
                        sourceAudioTrackCount: sourceAudioTracks.count,
                        mediaTrackIndex: trackOffset + 1,
                        mediaTrackCount: sourceAudioTracks.count,
                        clip: clip
                    )
                } catch {
                    diagnosePreparation(
                        step: .insertAudioTrack,
                        phase: .failure,
                        sourceIndex: sourceIndex,
                        sourceCount: sourceCount,
                        sourceFileSizeBytes: sourceFileSizeBytes,
                        sourceAudioTrackCount: sourceAudioTracks.count,
                        mediaTrackIndex: trackOffset + 1,
                        mediaTrackCount: sourceAudioTracks.count,
                        clip: clip,
                        error: error
                    )
                    if let createdTrack, createdTrack.segments.isEmpty {
                        composition.removeTrack(createdTrack)
                    }
                }
            }
        }

        let requiredEnd = CMTime(
            seconds: config.timelineStart + config.duration,
            preferredTimescale: timescale
        )
        if composition.duration < requiredEnd {
            composition.insertEmptyTimeRange(CMTimeRange(
                start: composition.duration,
                duration: CMTimeSubtract(requiredEnd, composition.duration)
            ))
        }
        return composition
    }

    private func diagnosePreparation(
        step: VideoExportDiagnosticEvent.PreparationStep,
        phase: VideoExportDiagnosticEvent.Phase,
        sourceIndex: Int? = nil,
        sourceCount: Int? = nil,
        sourceFileSizeBytes: Int64? = nil,
        sourceVideoTrackCount: Int? = nil,
        sourceAudioTrackCount: Int? = nil,
        mediaTrackIndex: Int? = nil,
        mediaTrackCount: Int? = nil,
        sourceSize: VideoExportDiagnosticEvent.SourceSize? = nil,
        sourceFramesPerSecond: Double? = nil,
        clip: TimelineClip? = nil,
        error: Error? = nil
    ) {
        let nsError = error as NSError?
        deliverDiagnostic(.init(
            stage: .prepareTimeline,
            phase: phase,
            errorDomain: nsError?.domain,
            errorCode: nsError?.code,
            sourceSize: sourceSize,
            sourceFramesPerSecond: sourceFramesPerSecond,
            preparationStep: step,
            sourceIndex: sourceIndex,
            sourceCount: sourceCount,
            sourceFileSizeBytes: sourceFileSizeBytes,
            sourceVideoTrackCount: sourceVideoTrackCount,
            sourceAudioTrackCount: sourceAudioTrackCount,
            mediaTrackIndex: mediaTrackIndex,
            mediaTrackCount: mediaTrackCount,
            timelineStartSeconds: clip?.timelineStart,
            timelineDurationSeconds: clip?.duration
        ))
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

        diagnose(
            stage: stage,
            phase: .failure,
            frameIndex: frameIndex,
            totalFrames: totalFrames,
            writer: writer,
            inputReady: inputReady,
            error: writer?.error ?? error
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
        if event.phase == .failure, event.stage != .exportFailed {
            didReportPreciseFailure = true
        }
        config.diagnosticsHandler?(event)
        diagnosticDeliveryLock.unlock()
    }

    private func deliverLatestRenderDiagnostic(from tracker: TimelineRenderDiagnosticStageTracker?) {
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

    private func diagnosticFileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }
        return Int64(fileSize)
    }

    private func skippedVideoWarning(for clip: TimelineClip, asset: MediaAsset) -> VideoExportWarning {
        VideoExportWarning(
            kind: .videoSegmentSkipped,
            clipID: clip.id,
            sourceDisplayName: asset.displayName,
            timelineStart: clip.timelineStart,
            duration: clip.duration
        )
    }

    private func audioTrack(
        _ track: AVCompositionTrack,
        hasSegmentOverlapping destinationRange: CMTimeRange
    ) -> Bool {
        track.segments.contains { segment in
            CMTimeRangeGetIntersection(
                segment.timeMapping.target,
                otherRange: destinationRange
            ).duration > .zero
        }
    }

    private func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }

    private func makeOverlayCompositions() throws -> [OverlayComposition] {
        let overlayClips = project.enabledClips(
            kind: .overlay,
            timelineStart: config.timelineStart,
            duration: config.duration
        )
        guard !overlayClips.isEmpty || config.codec.exportMode == .video else {
            throw OverlayVideoError.invalidConfiguration("Timeline overlay export requires at least one enabled overlay clip.")
        }

        return try overlayClips.map { clip in
            guard let overlayAsset = project.asset(id: clip.assetID), overlayAsset.kind == .activity else {
                throw OverlayVideoError.invalidConfiguration("Timeline overlay clip references a missing activity asset.")
            }
            guard let series = telemetrySeriesByAssetID[overlayAsset.id] else {
                throw OverlayVideoError.invalidConfiguration("Timeline overlay clip has no loaded telemetry series.")
            }
            let renderer = OverlayRenderer(
                series: series,
                config: OverlayRenderConfig(
                    size: CGSize(width: config.width, height: config.height),
                    timeSync: TelemetryTimeSync(videoSyncTime: 0, fitSyncTime: clip.sourceIn - clip.timelineStart),
                    activityOffsetMilliseconds: overlayAsset.activityOffsetMilliseconds,
                    fitClockOffsetMilliseconds: overlayAsset.fitClockOffsetMilliseconds,
                    layout: clip.layout ?? .default,
                    distanceUnit: clip.distanceUnit ?? project.distanceUnit,
                    timeZone: project.displayTimeZone(for: overlayAsset),
                    activityTrim: config.activityTrim
                )
            )
            return OverlayComposition(clip: clip, series: series, renderer: renderer)
        }
    }

    private func validateTransparentConfiguration() throws {
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
        guard config.timelineStart.isFinite, config.timelineStart >= 0 else {
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

    private func encoderFrameRateValue(_ framesPerSecond: Double) throws -> Int {
        let rounded = framesPerSecond.rounded()
        guard rounded.isFinite,
              rounded >= 1,
              rounded <= Double(Int.max) else {
            throw OverlayVideoError.invalidConfiguration("Output frame rate is too large for the encoder.")
        }
        return Int(rounded)
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

    private func makeTemporaryOutputURL(tag: String) -> URL {
        TransparentVideoWriter.makeTemporaryOutputURL(
            for: outputURL,
            tag: tag,
            fallbackBaseName: tag,
            directory: config.temporaryDirectory
        )
    }

    private func removePartialOutput(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func clearPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        memset(baseAddress, 0, bytesPerRow * height)
    }

    private func describe(error: Error?, codec: OverlayVideoCodec) -> String {
        guard let error else {
            return "AVAssetWriter failed while using \(codec.displayName)."
        }
        return "\(codec.displayName): \(error.localizedDescription)"
    }

    private struct OverlayComposition {
        var clip: TimelineClip
        var series: TelemetrySeries
        var renderer: OverlayRenderer
    }
}

private final class TimelineRenderDiagnosticStageTracker: @unchecked Sendable {
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

#endif
