import Foundation
@testable import OverlayCore
import XCTest

final class VideoExportOperationTests: XCTestCase {
    func testCancellationReturnsWithoutWaitingForBlockedCleanupAndRejectsAnotherExport() throws {
        let cancelled = ExportOperationFlag()
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        var lateCallbacks = 0
        var sawCancellation = false
        defer { releaseAndWaitForCleanup(release, finished: finished) }
        let start = ProcessInfo.processInfo.systemUptime

        XCTAssertThrowsError(try VideoExportSupport.performWriting(
            cancellationHandler: { cancelled.value },
            progressHandler: { _, _ in lateCallbacks += 1 },
            diagnosticsHandler: { _ in lateCallbacks += 1 }
        ) { control in
            defer { finished.signal() }
            cancelled.value = true
            release.wait() // Simulates AVAssetWriter.cancelWriting() not returning.
            sawCancellation = control.isCancelled
            control.recordProgress(30, 300)
            control.recordDiagnostic(.init(stage: .awaitReady, phase: .end))
        }) { error in
            guard case OverlayVideoError.cancelled = error else { return XCTFail("Expected cancellation, got \(error)") }
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
        XCTAssertEqual(finished.wait(timeout: .now()), .timedOut)
        XCTAssertThrowsError(try VideoExportSupport.performWriting(cancellationHandler: nil) { _ in
            XCTFail("A new writer must not start during deferred cleanup")
        }) { XCTAssertEqual($0 as? VideoExportWaitError, .cleanupPending) }

        releaseAndWaitForCleanup(release, finished: finished)
        XCTAssertTrue(sawCancellation)
        XCTAssertEqual(lateCallbacks, 0)
    }

    func testStalledWriterReturnsAnErrorWhileWorkerKeepsItsTemporaryFile() throws {
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = file.appendingPathExtension("mov")
        let original = Data("existing export".utf8)
        try original.write(to: destination)
        defer {
            releaseAndWaitForCleanup(release, finished: finished)
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: destination)
        }

        XCTAssertThrowsError(try VideoExportSupport.performWriting(
            cancellationHandler: nil, renderTimeout: 0.01
        ) { control in
            defer { try? FileManager.default.removeItem(at: file); finished.signal() }
            try Data("partial output".utf8).write(to: file)
            control.recordDiagnostic(.init(stage: .awaitReady, phase: .update, frameIndex: 12))
            release.wait()
            XCTAssertTrue(control.isCancelled)
            XCTAssertThrowsError(try VideoExportSupport.installCompletedOutput(
                from: file, to: destination, cancellationHandler: { control.isCancelled }
            ))
        }) { XCTAssertEqual($0 as? VideoExportWaitError, .stalled) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        releaseAndWaitForCleanup(release, finished: finished)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: destination), original)
    }

    func testRepeatedReadinessHeartbeatsDoNotHideAStall() throws {
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        defer { releaseAndWaitForCleanup(release, finished: finished) }
        XCTAssertThrowsError(try VideoExportSupport.performWriting(
            cancellationHandler: nil, renderTimeout: 0.02
        ) { control in
            defer { finished.signal() }
            while !control.isCancelled {
                control.recordDiagnostic(.init(stage: .awaitReady, phase: .update, frameIndex: 12))
                Thread.sleep(forTimeInterval: 0.005)
            }
            release.wait()
        }) { XCTAssertEqual($0 as? VideoExportWaitError, .stalled) }
    }

    func testAdvancingFramesKeepTheWriterAlive() throws {
        let result = try VideoExportSupport.performWriting(cancellationHandler: nil, renderTimeout: 0.04) { control in
            for frame in 0..<20 {
                control.recordDiagnostic(.init(stage: .awaitReady, phase: .update, frameIndex: frame))
                Thread.sleep(forTimeInterval: 0.01)
            }
            return 20
        }
        XCTAssertEqual(result, 20)
    }

    func testFinishWritingHasABoundedWait() throws {
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        defer { releaseAndWaitForCleanup(release, finished: finished) }
        XCTAssertThrowsError(try VideoExportSupport.performWriting(
            cancellationHandler: nil, finishTimeout: 0.01
        ) { control in
            defer { finished.signal() }
            control.recordDiagnostic(.init(stage: .finishWriter, phase: .begin))
            release.wait()
        }) { XCTAssertEqual($0 as? VideoExportWaitError, .stalled) }
    }

    func testCancellationDoesNotAbandonAnOutputReplacementAlreadyInProgress() throws {
        let cancelled = ExportOperationFlag()
        let replacing = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let returned = expectation(description: "Real installation result returned")
        let observedEarlyReturn = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { returned.fulfill(); observedEarlyReturn.signal() }
            do {
                let value = try VideoExportSupport.performWriting(cancellationHandler: { cancelled.value }) { control in
                    control.recordDiagnostic(.init(stage: .installOutput, phase: .begin))
                    replacing.signal()
                    release.wait()
                    return 42
                }
                XCTAssertEqual(value, 42)
            } catch { XCTFail("Must report the actual replacement result: \(error)") }
        }
        XCTAssertEqual(replacing.wait(timeout: .now() + 1), .success)
        cancelled.value = true
        XCTAssertEqual(observedEarlyReturn.wait(timeout: .now() + 0.1), .timedOut)
        release.signal()
        wait(for: [returned], timeout: 1)
    }

    private func releaseAndWaitForCleanup(_ release: DispatchSemaphore, finished: DispatchSemaphore) {
        release.signal()
        // Some tests call this before their defer to assert the post-cleanup state.
        _ = finished.wait(timeout: .now() + 0.2)
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while ProcessInfo.processInfo.systemUptime < deadline {
            do {
                _ = try VideoExportSupport.performWriting(cancellationHandler: nil) { _ in 0 }
                return
            } catch VideoExportWaitError.cleanupPending { Thread.sleep(forTimeInterval: 0.001) }
            catch { XCTFail("Unexpected cleanup error: \(error)"); return }
        }
        XCTFail("Deferred writer cleanup did not finish")
    }
}

private final class ExportOperationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return flag }
        set { lock.lock(); flag = newValue; lock.unlock() }
    }
}
