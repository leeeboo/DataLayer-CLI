#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

enum TimelineSegmentDecodeStrategy: Int, CaseIterable, Sendable {
    case primary
    case nativePixelFormatWithPreroll
    case softwareWithPreroll
}

protocol TimelineSegmentDecodeAttempt: AnyObject {
    var reader: AVAssetReader? { get }
    var status: AVAssetReader.Status { get }
    var error: Error? { get }

    func copyNextSampleBuffer() -> CMSampleBuffer?
    func cancel()
}

final class ResilientTimelineSegmentReader: @unchecked Sendable {
    typealias AttemptFactory = (
        TimelineVideoSegment,
        TimelineSegmentDecodeStrategy,
        CMTime
    ) throws -> TimelineSegmentDecodeAttempt

    private enum AttemptTerminal {
        case completed
        case failed
    }

    private struct RecoveryAction {
        let shouldStartNextAttempt: Bool
        let warning: VideoExportWarning?
    }

    private static let maximumBufferedSamples = 2
    private static let pollInterval: TimeInterval = 0.05

    private let videoSettings: [String: Any]
    private let attemptTimeout: TimeInterval
    private let initialStrategy: TimelineSegmentDecodeStrategy
    private let attemptFactory: AttemptFactory?
    private let diagnosticsHandler: ((VideoExportDiagnosticEvent) -> Void)?
    private let warningHandler: (VideoExportWarning) -> Void
    private let condition = NSCondition()
    private let decodeQueue = DispatchQueue(label: "run.libo.overlay.segment-decoder", qos: .userInitiated)

    private var segment: TimelineVideoSegment?
    private var strategyIndex = 0
    private var generation = 0
    private var attempt: TimelineSegmentDecodeAttempt?
    private var samples: [CMSampleBuffer] = []
    private var terminal: AttemptTerminal?
    private var didProduceSample = false
    private var lastActivityUptime: TimeInterval = 0
    private var cancellationRequested = false
    private var skipped = false
    private var didReportSkippedWarning = false
    private var lastFailure: NSError?
    private var operationStep: VideoExportDiagnosticEvent.OperationStep = .decoderQueued
    private var sourceIndex: Int?
    private var activeWork = Set<UUID>()

    var reader: AVAssetReader? {
        condition.lock()
        defer { condition.unlock() }
        return attempt?.reader
    }

    init(
        videoSettings: [String: Any],
        attemptTimeout: TimeInterval = 8,
        initialStrategy: TimelineSegmentDecodeStrategy = .primary,
        warningHandler: @escaping (VideoExportWarning) -> Void,
        attemptFactory: AttemptFactory? = nil,
        diagnosticsHandler: ((VideoExportDiagnosticEvent) -> Void)? = nil
    ) {
        self.videoSettings = videoSettings
        self.attemptTimeout = max(0.05, attemptTimeout)
        self.initialStrategy = initialStrategy
        self.warningHandler = warningHandler
        self.attemptFactory = attemptFactory
        self.diagnosticsHandler = diagnosticsHandler
    }

    func open(_ segment: TimelineVideoSegment, sourceIndex: Int? = nil) throws {
        condition.lock()
        let canOpen = self.segment == nil && attempt == nil
        let wasCancelled = cancellationRequested
        condition.unlock()
        precondition(canOpen, "Timeline segment reader must be closed before reuse.")
        if wasCancelled {
            throw OverlayVideoError.cancelled
        }

        condition.lock()
        self.segment = segment
        self.sourceIndex = sourceIndex
        strategyIndex = initialStrategy.rawValue
        terminal = nil
        samples.removeAll(keepingCapacity: true)
        didProduceSample = false
        skipped = false
        didReportSkippedWarning = false
        lastActivityUptime = ProcessInfo.processInfo.systemUptime
        condition.unlock()
        startAttempt(targetSourceTime: segment.sourceRange.start)
    }

    func copyNextSampleBuffer(targetSourceTime: CMTime) throws -> CMSampleBuffer? {
        while true {
            condition.lock()
            if cancellationRequested {
                condition.unlock()
                throw OverlayVideoError.cancelled
            }
            if let sample = samples.first {
                samples.removeFirst()
                condition.broadcast()
                condition.unlock()
                return sample
            }
            if skipped {
                condition.unlock()
                return nil
            }
            if terminal == .completed, didProduceSample {
                condition.unlock()
                return nil
            }

            let now = ProcessInfo.processInfo.systemUptime
            if terminal == nil, now - lastActivityUptime >= attemptTimeout {
                // A blocked AVFoundation read still owns decoder resources. Do not cancel it
                // concurrently or start a replacement while it is unwinding.
                let error = OverlayVideoError.unreadableVideo(
                    "Source video reading failed.",
                    underlying: NSError(domain: "run.libo.datalayer-studio.decoder", code: 1)
                )
                let failure = VideoExportDiagnosticEvent(
                    stage: .readSource, phase: .failure,
                    errorDomain: (error as NSError).domain, errorCode: (error as NSError).code,
                    sourceIndex: sourceIndex, operationStep: operationStep,
                    decodeAttempt: strategyIndex + 1,
                    decodeTimeoutSeconds: attemptTimeout,
                    decodeIdleSeconds: now - lastActivityUptime,
                    decodeProducedSample: didProduceSample,
                    sourceTimeSeconds: CMTimeGetSeconds(targetSourceTime)
                )
                generation &+= 1
                markPendingWorkLocked()
                attempt = nil
                condition.broadcast()
                condition.unlock()
                diagnosticsHandler?(failure)
                throw error
            }
            if terminal != nil {
                let action = prepareRecoveryLocked()
                condition.unlock()
                if let warning = action.warning {
                    warningHandler(warning)
                }
                if action.shouldStartNextAttempt {
                    startAttempt(targetSourceTime: targetSourceTime)
                    continue
                }
                return nil
            }

            let remaining = max(0.001, attemptTimeout - (now - lastActivityUptime))
            condition.wait(until: Date(timeIntervalSinceNow: min(Self.pollInterval, remaining)))
            condition.unlock()
        }
    }

    func cancelReading() {
        condition.lock()
        cancellationRequested = true
        markPendingWorkLocked()
        generation &+= 1
        self.attempt = nil
        samples.removeAll(keepingCapacity: false)
        terminal = .failed
        condition.broadcast()
        condition.unlock()
    }

    func close() {
        condition.lock()
        markPendingWorkLocked()
        generation &+= 1
        self.attempt = nil
        segment = nil
        sourceIndex = nil
        samples.removeAll(keepingCapacity: true)
        terminal = nil
        didProduceSample = false
        skipped = false
        didReportSkippedWarning = false
        condition.broadcast()
        condition.unlock()
    }

    private func prepareRecoveryLocked() -> RecoveryAction {
        if lastFailure == nil {
            lastFailure = NSError(domain: "run.libo.datalayer-studio.decoder", code: terminal == .completed ? 2 : 3)
        }
        generation &+= 1
        attempt = nil
        samples.removeAll(keepingCapacity: true)
        terminal = nil
        didProduceSample = false

        if strategyIndex + 1 < TimelineSegmentDecodeStrategy.allCases.count {
            strategyIndex += 1
            lastActivityUptime = ProcessInfo.processInfo.systemUptime
            return RecoveryAction(
                shouldStartNextAttempt: true,
                warning: nil
            )
        }

        skipped = true
        let warning: VideoExportWarning?
        if !didReportSkippedWarning, let segment {
            didReportSkippedWarning = true
            warning = VideoExportWarning(
                kind: .videoSegmentSkipped,
                clipID: segment.clipID,
                sourceDisplayName: segment.sourceDisplayName,
                timelineStart: CMTimeGetSeconds(segment.timelineRange.start),
                duration: CMTimeGetSeconds(segment.timelineRange.duration),
                error: lastFailure,
                decodeAttemptCount: strategyIndex + 1
            )
        } else {
            warning = nil
        }
        return RecoveryAction(
            shouldStartNextAttempt: false,
            warning: warning
        )
    }

    private func startAttempt(targetSourceTime: CMTime) {
        condition.lock()
        guard let segment, !cancellationRequested, !skipped else {
            condition.unlock()
            return
        }
        generation &+= 1
        let attemptGeneration = generation
        let workID = UUID()
        activeWork.insert(workID)
        let strategy = TimelineSegmentDecodeStrategy.allCases[strategyIndex]
        operationStep = .decoderQueued
        let sourceIndex = self.sourceIndex
        lastFailure = nil
        lastActivityUptime = ProcessInfo.processInfo.systemUptime
        condition.unlock()
        checkpoint(.decoderQueued, generation: attemptGeneration, attempt: strategy.rawValue + 1,
                   sourceIndex: sourceIndex)

        decodeQueue.async {
            defer {
                self.condition.lock()
                self.activeWork.remove(workID)
                VideoExportCleanup.setPending(false, id: workID)
                self.condition.unlock()
            }
            self.condition.lock()
            let shouldStart = self.generation == attemptGeneration && !self.cancellationRequested && !self.skipped
            self.condition.unlock()
            guard shouldStart else { return }
            let sourceURL = (segment.asset as? AVURLAsset)?.url
            let accessedSource = sourceURL?.startAccessingSecurityScopedResource() == true
            defer { if accessedSource { sourceURL?.stopAccessingSecurityScopedResource() } }
            self.checkpoint(.decoderCreateReader, generation: attemptGeneration,
                            attempt: strategy.rawValue + 1, sourceIndex: sourceIndex)
            let newAttempt: TimelineSegmentDecodeAttempt
            do {
                if let factory = self.attemptFactory {
                    newAttempt = try factory(segment, strategy, targetSourceTime)
                } else {
                    newAttempt = try AVTimelineSegmentDecodeAttempt(
                        segment: segment, strategy: strategy, targetSourceTime: targetSourceTime,
                        baseVideoSettings: self.videoSettings,
                        willStartReading: { [weak self] in
                            self?.checkpoint(.decoderStartReader, generation: attemptGeneration,
                                             attempt: strategy.rawValue + 1, sourceIndex: sourceIndex)
                        }
                    )
                }
            } catch {
                self.finishAttempt(generation: attemptGeneration, terminal: .failed, error: error as NSError)
                return
            }

            // Creation, reads and cancellation all run on this queue. Retain the attempt
            // until an in-flight read returns, even if the consumer has already stopped.
            // shortcut: in-process callers cannot kill a native read; block new exports until it returns.
            defer { newAttempt.cancel() }
            self.condition.lock()
            guard self.generation == attemptGeneration,
                  !self.cancellationRequested,
                  !self.skipped else {
                self.condition.unlock()
                return
            }
            self.attempt = newAttempt
            self.lastActivityUptime = ProcessInfo.processInfo.systemUptime
            self.condition.broadcast()
            self.condition.unlock()

            while true {
                self.condition.lock()
                let shouldRead = self.generation == attemptGeneration && !self.cancellationRequested && !self.skipped
                let isFirstRead = !self.didProduceSample
                if shouldRead { self.operationStep = .decoderCopySample }
                self.condition.unlock()
                guard shouldRead else { return }
                if isFirstRead {
                    self.checkpoint(.decoderCopySample, generation: attemptGeneration,
                                    attempt: strategy.rawValue + 1, sourceIndex: sourceIndex)
                }
                let sample = autoreleasepool {
                    newAttempt.copyNextSampleBuffer()
                }

                self.condition.lock()
                guard self.generation == attemptGeneration,
                      !self.cancellationRequested,
                      !self.skipped else {
                    self.condition.unlock()
                    return
                }

                guard let sample else {
                    self.lastFailure = newAttempt.error as NSError?
                    self.attempt = nil
                    self.terminal = newAttempt.status == .failed ? .failed : .completed
                    self.lastActivityUptime = ProcessInfo.processInfo.systemUptime
                    self.condition.broadcast()
                    self.condition.unlock()
                    return
                }

                while self.samples.count >= Self.maximumBufferedSamples,
                      self.generation == attemptGeneration,
                      !self.cancellationRequested,
                      !self.skipped {
                    self.condition.wait()
                }
                guard self.generation == attemptGeneration,
                      !self.cancellationRequested,
                      !self.skipped else {
                    self.condition.unlock()
                    return
                }
                self.samples.append(sample)
                self.didProduceSample = true
                self.lastActivityUptime = ProcessInfo.processInfo.systemUptime
                self.condition.broadcast()
                self.condition.unlock()
                if isFirstRead {
                    self.checkpoint(.decoderSampleReady, generation: attemptGeneration,
                                    attempt: strategy.rawValue + 1, sourceIndex: sourceIndex)
                }
            }
        }
    }

    private func markPendingWorkLocked() {
        for id in activeWork { VideoExportCleanup.setPending(true, id: id) }
    }

    /// No callbacks run while the reader lock is held, and native read events are not emitted per frame.
    private func checkpoint(_ step: VideoExportDiagnosticEvent.OperationStep, generation: Int,
                            attempt: Int, sourceIndex: Int?) {
        condition.lock()
        let isCurrent = self.generation == generation && !cancellationRequested && !skipped
        if isCurrent { operationStep = step }
        condition.unlock()
        guard isCurrent else { return }
        diagnosticsHandler?(.init(stage: .readSource, phase: .update,
            sourceIndex: sourceIndex, operationStep: step, decodeAttempt: attempt))
    }

    private func finishAttempt(generation: Int, terminal: AttemptTerminal, error: NSError? = nil) {
        condition.lock()
        guard self.generation == generation,
              !cancellationRequested,
              !skipped else {
            condition.unlock()
            return
        }
        attempt = nil
        self.terminal = terminal
        lastFailure = error
        lastActivityUptime = ProcessInfo.processInfo.systemUptime
        condition.broadcast()
        condition.unlock()
    }
}

private final class AVTimelineSegmentDecodeAttempt: TimelineSegmentDecodeAttempt {
    let reader: AVAssetReader?
    private let output: AVAssetReaderTrackOutput
    private let cancellationLock = NSLock()
    private var didCancel = false

    var status: AVAssetReader.Status {
        reader?.status ?? .failed
    }

    var error: Error? {
        reader?.error
    }

    init(
        segment: TimelineVideoSegment,
        strategy: TimelineSegmentDecodeStrategy,
        targetSourceTime: CMTime,
        baseVideoSettings: [String: Any],
        willStartReading: () -> Void
    ) throws {
        let reader = try AVAssetReader(asset: segment.asset)
        reader.timeRange = Self.timeRange(
            for: segment,
            strategy: strategy,
            targetSourceTime: targetSourceTime
        )
        let output = AVAssetReaderTrackOutput(
            track: segment.videoTrack,
            outputSettings: Self.outputSettings(
                base: baseVideoSettings,
                track: segment.videoTrack,
                strategy: strategy
            )
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw OverlayVideoError.unreadableVideo(
                "Could not prepare a timeline video segment for reading."
            )
        }
        reader.add(output)
        willStartReading()
        guard reader.startReading() else {
            throw OverlayVideoError.unreadableVideo(
                reader.error?.localizedDescription
                    ?? "Could not start reading a timeline video segment.", underlying: reader.error
            )
        }
        self.reader = reader
        self.output = output
    }

    func copyNextSampleBuffer() -> CMSampleBuffer? {
        output.copyNextSampleBuffer()
    }

    func cancel() {
        cancellationLock.lock()
        let shouldCancel = !didCancel
        didCancel = true
        cancellationLock.unlock()
        if shouldCancel {
            reader?.cancelReading()
        }
    }

    private static func timeRange(
        for segment: TimelineVideoSegment,
        strategy: TimelineSegmentDecodeStrategy,
        targetSourceTime: CMTime
    ) -> CMTimeRange {
        guard strategy != .primary else { return segment.sourceRange }
        let trackRange = segment.videoTrack.timeRange
        let requestedStart = targetSourceTime.isValid ? targetSourceTime : segment.sourceRange.start
        let preroll = CMTime(seconds: 2, preferredTimescale: max(600, requestedStart.timescale))
        let start = maxTime(trackRange.start, CMTimeSubtract(requestedStart, preroll))
        let end = minTime(CMTimeRangeGetEnd(trackRange), CMTimeRangeGetEnd(segment.sourceRange))
        guard end > start else { return segment.sourceRange }
        return CMTimeRange(start: start, duration: CMTimeSubtract(end, start))
    }

    private static func outputSettings(
        base: [String: Any],
        track: AVAssetTrack,
        strategy: TimelineSegmentDecodeStrategy
    ) -> [String: Any] {
        guard strategy != .primary else { return base }
        var settings = base
        let sourceCodec = track.formatDescriptions.first.map {
            CMFormatDescriptionGetMediaSubType($0 as! CMFormatDescription)
        }
        if strategy == .nativePixelFormatWithPreroll,
           sourceCodec == kCMVideoCodecType_HEVC || sourceCodec == kCMVideoCodecType_H264 {
            settings[kCVPixelBufferPixelFormatTypeKey as String] = highPrecisionBiPlanarPixelFormat(track: track)
        }
        if strategy == .softwareWithPreroll {
            settings[AVVideoDecompressionPropertiesKey] = [
                kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: false
            ]
        }
        return settings
    }

    private static func highPrecisionBiPlanarPixelFormat(track: AVAssetTrack) -> OSType {
        guard let description = track.formatDescriptions.first else {
            return kCVPixelFormatType_64RGBAHalf
        }
        guard let extensions = CMFormatDescriptionGetExtensions(description as! CMFormatDescription) as NSDictionary? else {
            return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        }
        let fullRange = (extensions[kCMFormatDescriptionExtension_FullRangeVideo] as? NSNumber)?.boolValue == true
        return fullRange
            ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
            : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
    }

    private static func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }

    private static func maxTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) >= 0 ? lhs : rhs
    }
}

#endif
