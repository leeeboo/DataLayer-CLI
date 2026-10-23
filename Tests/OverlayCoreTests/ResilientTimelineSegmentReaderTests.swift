import AVFoundation
import CoreMedia
import Foundation
@testable import OverlayCore
import XCTest

final class ResilientTimelineSegmentReaderTests: XCTestCase {
    func testTimedOutReadDoesNotCancelOrReplaceAnInFlightDecoder() throws {
        let composition = AVMutableComposition()
        let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))
        let segment = TimelineVideoSegment(clipID: "blocked", sourceDisplayName: "camera.mov", asset: composition,
            videoTrack: track, timelineRange: range, sourceRange: range, sourceTransform: .identity)
        let attempt = NonCooperativeDecodeAttempt()
        let diagnostics = ReaderDiagnosticEvents()
        let reader = ResilientTimelineSegmentReader(videoSettings: [:], attemptTimeout: 0.05,
            warningHandler: { _ in XCTFail("A still-running decoder must fail export, not silently skip content.") },
            attemptFactory: { _, _, _ in attempt }, diagnosticsHandler: diagnostics.record)
        defer { attempt.releaseRead(); reader.close() }
        try reader.open(segment, sourceIndex: 4)
        XCTAssertTrue(attempt.started.wait(timeout: .now() + 1) == .success)
        XCTAssertThrowsError(try reader.copyNextSampleBuffer(targetSourceTime: .zero)) { error in
            let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            XCTAssertEqual(underlying?.domain, "run.libo.datalayer-studio.decoder")
            XCTAssertEqual(underlying?.code, 1)
        }
        reader.cancelReading()
        reader.close()
        XCTAssertEqual(attempt.cancelCount, 0, "Cancellation must wait for the in-flight copy to return.")
        XCTAssertEqual(attempt.copyCount, 1, "Retry must not overlap the blocked reader.")
        XCTAssertThrowsError(try VideoExportCleanup.check()) {
            XCTAssertEqual($0 as? VideoExportWaitError, .cleanupPending)
        }
        attempt.releaseRead()
        XCTAssertTrue(attempt.cancelled.wait(timeout: .now() + 1) == .success)
        XCTAssertEqual(attempt.cancelCount, 1)
        let cleanupDeadline = ProcessInfo.processInfo.systemUptime + 1
        while ProcessInfo.processInfo.systemUptime < cleanupDeadline {
            if (try? VideoExportCleanup.check()) != nil { break }
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertNoThrow(try VideoExportCleanup.check())
        let failure = try XCTUnwrap(diagnostics.events.first { $0.phase == .failure })
        XCTAssertEqual(failure.stage, .readSource)
        XCTAssertEqual(failure.operationStep, .decoderCopySample)
        XCTAssertEqual(failure.decodeAttempt, 1)
        XCTAssertEqual(failure.sourceIndex, 4)
        XCTAssertEqual(failure.decodeTimeoutSeconds, 0.05)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(failure.decodeIdleSeconds), 0.05)
        XCTAssertEqual(failure.decodeProducedSample, false)
        XCTAssertEqual(failure.sourceTimeSeconds, 0)
    }

    func testReaderCreationTimeoutIsDistinctFromNativeSampleRead() throws {
        let composition = AVMutableComposition()
        let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))
        let segment = TimelineVideoSegment(clipID: "private", sourceDisplayName: "private.mov", asset: composition,
            videoTrack: track, timelineRange: range, sourceRange: range, sourceTransform: .identity)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let attempt = NonCooperativeDecodeAttempt()
        let diagnostics = ReaderDiagnosticEvents()
        let reader = ResilientTimelineSegmentReader(videoSettings: [:], attemptTimeout: 0.05,
            warningHandler: { _ in XCTFail("An active factory must not be replaced.") },
            attemptFactory: { _, _, _ in entered.signal(); release.wait(); return attempt },
            diagnosticsHandler: diagnostics.record)
        defer { release.signal(); reader.close() }
        try reader.open(segment)
        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        XCTAssertThrowsError(try reader.copyNextSampleBuffer(targetSourceTime: .zero))
        let failure = try XCTUnwrap(diagnostics.events.first { $0.phase == .failure })
        XCTAssertEqual(failure.operationStep, .decoderCreateReader)
        XCTAssertEqual(failure.decodeAttempt, 1)
        XCTAssertEqual(failure.decodeTimeoutSeconds, 0.05)
        XCTAssertEqual(failure.decodeProducedSample, false)
        XCTAssertEqual(attempt.copyCount, 0)
        XCTAssertEqual(attempt.cancelCount, 0)
        release.signal()
        XCTAssertEqual(attempt.cancelled.wait(timeout: .now() + 1), .success)
    }

    func testCancellationReturnsBeforeBlockedReadAndDefersCleanup() throws {
        let composition = AVMutableComposition()
        let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))
        let segment = TimelineVideoSegment(clipID: "cancelled", sourceDisplayName: "camera.mov", asset: composition,
            videoTrack: track, timelineRange: range, sourceRange: range, sourceTransform: .identity)
        let attempt = NonCooperativeDecodeAttempt()
        let reader = ResilientTimelineSegmentReader(videoSettings: [:], warningHandler: { _ in },
            attemptFactory: { _, _, _ in attempt })
        defer { attempt.releaseRead(); reader.close() }
        try reader.open(segment)
        XCTAssertTrue(attempt.started.wait(timeout: .now() + 1) == .success)
        reader.cancelReading()
        reader.close()
        XCTAssertThrowsError(try reader.copyNextSampleBuffer(targetSourceTime: .zero)) { error in
            guard case OverlayVideoError.cancelled = error else { return XCTFail("Expected cancellation") }
        }
        XCTAssertEqual(attempt.cancelCount, 0)
        attempt.releaseRead()
        XCTAssertTrue(attempt.cancelled.wait(timeout: .now() + 1) == .success)
        XCTAssertEqual(attempt.cancelCount, 1)
    }

    func testFailedReaderCreationKeepsUnderlyingErrorInSkippedWarning() throws {
        let composition = AVMutableComposition()
        let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))
        let segment = TimelineVideoSegment(clipID: "private", sourceDisplayName: "private.mov", asset: composition,
                                           videoTrack: track, timelineRange: range, sourceRange: range, sourceTransform: .identity)
        var warnings: [VideoExportWarning] = []
        let reader = ResilientTimelineSegmentReader(videoSettings: [:], warningHandler: { warnings.append($0) },
            attemptFactory: { _, _, _ in
                throw OverlayVideoError.unreadableVideo("private path", underlying: NSError(domain: NSOSStatusErrorDomain, code: -12909))
            })
        defer { reader.close() }
        try reader.open(segment)
        XCTAssertNil(try reader.copyNextSampleBuffer(targetSourceTime: .zero))
        let warning = try XCTUnwrap(warnings.first)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warning.decodeAttemptCount, 3)
        XCTAssertEqual((warning.error?.userInfo[NSUnderlyingErrorKey] as? NSError)?.code, -12909)
    }

}

private final class ReaderDiagnosticEvents {
    private let lock = NSLock()
    private var stored: [VideoExportDiagnosticEvent] = []
    var events: [VideoExportDiagnosticEvent] { lock.withLock { stored } }
    func record(_ event: VideoExportDiagnosticEvent) { lock.withLock { stored.append(event) } }
}

final class NonCooperativeDecodeAttempt: TimelineSegmentDecodeAttempt, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let cancelled = DispatchSemaphore(value: 0)
    private let condition = NSCondition()
    private var released = false
    private var copies = 0
    private var cancellations = 0
    var reader: AVAssetReader? { nil }
    var status: AVAssetReader.Status { .reading }
    var error: Error? { nil }
    var copyCount: Int { condition.withLock { copies } }
    var cancelCount: Int { condition.withLock { cancellations } }
    func copyNextSampleBuffer() -> CMSampleBuffer? {
        condition.lock()
        copies += 1
        started.signal()
        while !released { condition.wait() }
        condition.unlock()
        return nil
    }
    func cancel() {
        condition.withLock { cancellations += 1 }
        cancelled.signal()
    }
    func releaseRead() {
        condition.withLock { released = true; condition.broadcast() }
    }
}
