import AVFoundation
import CoreMedia
import CoreVideo
@testable import OverlayCore
import XCTest

final class TransparentVideoWriterTests: XCTestCase {
    func testActivityAndClockOffsetsAreClampedIndependently() {
        var config = TransparentVideoWriterConfig(
            width: 64,
            height: 64,
            framesPerSecond: 30,
            duration: 1,
            activityOffsetMilliseconds: -2_000,
            fitClockOffsetMilliseconds: 2_000
        )

        XCTAssertEqual(config.activityOffsetMilliseconds, -999)
        XCTAssertEqual(config.fitClockOffsetMilliseconds, 999)

        config.activityOffsetMilliseconds = 2_000
        config.fitClockOffsetMilliseconds = -2_000
        XCTAssertEqual(config.activityOffsetMilliseconds, 999)
        XCTAssertEqual(config.fitClockOffsetMilliseconds, -999)
    }

    func testVideoErrorsExposeSpecificLocalizedDescription() {
        let error = OverlayVideoError.invalidConfiguration("Output bitrate must be positive.")

        XCTAssertEqual(error.localizedDescription, "Output bitrate must be positive.")
    }

    func testFractionalFrameRateDoesNotDriftOverLongExports() {
        let timing = TransparentVideoFrameTiming(framesPerSecond: 29.97, duration: 600)

        XCTAssertEqual(timing.framesPerSecond, 30_000.0 / 1_001.0, accuracy: 0.000_000_001)
        XCTAssertEqual(timing.frameCount, 17_983)
        XCTAssertEqual(CMTimeGetSeconds(timing.presentationTime(for: 17_982)), 599.9994, accuracy: 0.00001)
        XCTAssertLessThan(abs(CMTimeGetSeconds(timing.outputDuration) - 600), 1 / timing.framesPerSecond)
    }

    func testNTSCAliasFrameRatesUseExactRationalDurations() {
        let cases: [(alias: Double, exact: Double, timescale: CMTimeScale)] = [
            (23.976, 24_000.0 / 1_001.0, 24_000),
            (29.97, 30_000.0 / 1_001.0, 30_000),
            (59.94, 60_000.0 / 1_001.0, 60_000),
            (119.88, 120_000.0 / 1_001.0, 120_000)
        ]

        for item in cases {
            let timing = TransparentVideoFrameTiming(framesPerSecond: item.alias, duration: 1)
            XCTAssertEqual(timing.framesPerSecond, item.exact, accuracy: 0.000_000_001)
            XCTAssertEqual(timing.mediaTimeScale, item.timescale)
            XCTAssertEqual(timing.frameDuration, CMTime(value: 1_001, timescale: item.timescale))
        }
    }

    func testFrameRateMatrixDoesNotAccumulateDriftAtTenSecondsOrFourHours() {
        let frameRates = [
            24_000.0 / 1_001.0,
            24,
            25,
            30_000.0 / 1_001.0,
            30,
            50,
            60_000.0 / 1_001.0,
            60
        ]

        for frameRate in frameRates {
            for duration in [10.0, 4 * 60 * 60.0] {
                let timing = TransparentVideoFrameTiming(
                    framesPerSecond: frameRate,
                    duration: duration
                )
                let outputSeconds = CMTimeGetSeconds(timing.outputDuration)
                let oneFrame = CMTimeGetSeconds(timing.frameDuration)

                XCTAssertGreaterThanOrEqual(outputSeconds + 0.000_000_001, duration)
                XCTAssertLessThan(outputSeconds - duration, oneFrame + 0.000_000_001)
                XCTAssertEqual(
                    CMTimeGetSeconds(timing.presentationTime(for: timing.frameCount)),
                    Double(timing.frameCount) * oneFrame,
                    accuracy: 0.000_000_001
                )
            }
        }
    }

    func testNTSCTimingMatchesSourceFrameBoundary() {
        let fps = 30_000.0 / 1_001.0
        let duration = Double(10_049 * 1_001) / 30_000
        let timing = TransparentVideoFrameTiming(framesPerSecond: fps, duration: duration)

        XCTAssertEqual(timing.frameCount, 10_049)
        XCTAssertEqual(timing.mediaTimeScale, 30_000)
        XCTAssertEqual(timing.presentationTime(for: 10_048), CMTime(value: 10_048 * 1_001, timescale: 30_000))
        XCTAssertEqual(CMTimeGetSeconds(timing.outputDuration), duration, accuracy: 0.000000001)
    }

    func testFrameTimingSanitizesInvalidValues() {
        let timing = TransparentVideoFrameTiming(framesPerSecond: .nan, duration: -.infinity)

        XCTAssertEqual(timing.framesPerSecond, 1)
        XCTAssertEqual(timing.duration, 0)
        XCTAssertEqual(timing.frameCount, 1)
        XCTAssertFalse(timing.frameCountWasClamped)
        XCTAssertEqual(CMTimeGetSeconds(timing.presentationTime(for: -10)), 0, accuracy: 0.00001)
    }

    func testFrameTimingClampsOverflowingFrameCount() {
        let timing = TransparentVideoFrameTiming(
            framesPerSecond: .greatestFiniteMagnitude,
            duration: .greatestFiniteMagnitude
        )

        XCTAssertEqual(timing.frameCount, Int.max)
        XCTAssertTrue(timing.frameCountWasClamped)
    }

    func testWriterRejectsOverflowingFrameCountBeforeExport() {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-overflow-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: []),
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: .greatestFiniteMagnitude,
                duration: .greatestFiniteMagnitude
            )
        )

        XCTAssertThrowsError(try writer.write()) { error in
            guard case OverlayVideoError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testWriterRejectsInvalidDurationBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: 30,
                duration: 0
            )
        )
    }

    func testWriterRejectsInvalidBitrateBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: 30,
                duration: 1,
                averageBitRate: 0
            )
        )

        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: 30,
                duration: 1,
                averageBitRate: 1_000_000_001
            )
        )
    }

    func testWriterRejectsOddOutputDimensionsBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 1919,
                height: 1080,
                framesPerSecond: 30,
                duration: 1
            )
        )

        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 1920,
                height: 1079,
                framesPerSecond: 30,
                duration: 1
            )
        )
    }

    func testWriterRejectsOversizedOutputDimensionsBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 16_386,
                height: 1080,
                framesPerSecond: 30,
                duration: 1
            )
        )

        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 1920,
                height: 16_386,
                framesPerSecond: 30,
                duration: 1
            )
        )
    }

    func testWriterRejectsEncoderFrameRateOverflowBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: Double(Int.max) * 2,
                duration: Double.leastNormalMagnitude
            )
        )
    }

    func testWriterRejectsPlainVideoCodecBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: 1,
                duration: 1,
                codec: .hevc
            )
        )
    }

    func testWriterRejectsMissingOutputDirectoryBeforeExport() {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-output-dir-\(UUID().uuidString)")
            .appendingPathComponent("overlay.mov")
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: []),
            config: validTinyConfig()
        )

        XCTAssertThrowsError(try writer.write()) { error in
            guard case OverlayVideoError.invalidConfiguration(let message) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
            XCTAssertTrue(message.contains("Output directory does not exist"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testWriterRejectsDirectoryOutputPathBeforeExport() {
        let outputURL = FileManager.default.temporaryDirectory
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: []),
            config: validTinyConfig()
        )

        XCTAssertThrowsError(try writer.write()) { error in
            guard case OverlayVideoError.invalidConfiguration(let message) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
            XCTAssertTrue(message.contains("Output path must be a file"))
        }
    }

    func testTemporaryOutputIsWrittenInAppTemporaryDirectory() {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-target-\(UUID().uuidString)")
            .appendingPathComponent("overlay.mov")
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: []),
            config: validTinyConfig()
        )

        let temporaryURL = writer.makeTemporaryOutputURL()

        XCTAssertEqual(
            temporaryURL.deletingLastPathComponent().standardizedFileURL.path,
            FileManager.default.temporaryDirectory.standardizedFileURL.path
        )
        XCTAssertTrue(temporaryURL.lastPathComponent.hasPrefix("DataLayerStudio-\(ProcessInfo.processInfo.processIdentifier)-"))
        XCTAssertEqual(temporaryURL.pathExtension, "mov")
    }

    func testCleanupRemovesOnlyStaleDataLayerTemporaryOutputs() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("datalayer-temporary-cleanup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staleURL = directory
            .appendingPathComponent("DataLayerStudio-0-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let legacyURL = directory
            .appendingPathComponent("DataLayerStudio-legacy-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let otherURL = directory
            .appendingPathComponent("OtherApp-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let currentURL = TransparentVideoWriter(
            outputURL: directory
                .appendingPathComponent("current-\(UUID().uuidString)")
                .appendingPathExtension("mov"),
            series: TelemetrySeries(samples: []),
            config: validTinyConfig()
        ).makeTemporaryOutputURL()

        for url in [staleURL, legacyURL, otherURL, currentURL] {
            try Data([1]).write(to: url)
        }
        defer {
            try? fileManager.removeItem(at: directory)
        }

        TransparentVideoWriter.removeStaleTemporaryOutputs(in: directory)

        XCTAssertFalse(fileManager.fileExists(atPath: staleURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: otherURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: currentURL.path))
    }

    func testCrashRecoveryKeepsLiveWorkerAndRemovesDeadWorkerDirectory() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: directory) }
        let live = directory.appendingPathComponent("DataLayerStudio-0-worker-live")
        let dead = directory.appendingPathComponent("DataLayerStudio-0-worker-dead")
        for (url, pid) in [(live, ProcessInfo.processInfo.processIdentifier), (dead, 0)] {
            try manager.createDirectory(at: url, withIntermediateDirectories: false)
            try String(pid).write(to: url.appendingPathComponent("worker.pid"), atomically: true, encoding: .utf8)
            try manager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -120)], ofItemAtPath: url.path)
        }
        TransparentVideoWriter.removeStaleTemporaryOutputs(in: directory)
        XCTAssertTrue(manager.fileExists(atPath: live.path))
        XCTAssertFalse(manager.fileExists(atPath: dead.path))
    }

    /// 同名导出必须原子替换，且不得在目标目录留下任何同级文件：沙盒下
    /// NSSavePanel 只授权选中的文件本身，新建同级备份会越权报「没有权限」，
    /// 而替换其实已经完成，用户会看到「文件正确却提示导出失败」。
    func testCompletedOutputInstallationReplacesInPlaceWithoutSiblingFiles() throws {
        let fileManager = FileManager.default
        let destinationDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("datalayer-install-dir-\(UUID().uuidString)")
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let outputURL = destinationDirectory.appendingPathComponent("output.mov")
        let completedURL = fileManager.temporaryDirectory
            .appendingPathComponent("datalayer-install-completed-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let replacement = Data("completed replacement".utf8)
        try Data("existing output".utf8).write(to: outputURL)
        try replacement.write(to: completedURL)
        defer {
            try? fileManager.removeItem(at: destinationDirectory)
            try? fileManager.removeItem(at: completedURL)
        }

        try VideoExportSupport.installCompletedOutput(
            from: completedURL,
            to: outputURL,
            cancellationHandler: nil
        )

        XCTAssertEqual(try Data(contentsOf: outputURL), replacement)
        let remaining = try fileManager.contentsOfDirectory(
            atPath: destinationDirectory.path
        )
        XCTAssertEqual(remaining, ["output.mov"], "目标目录不应残留备份等同级文件")
    }

    func testCompletedOutputInstallationThrowsWhenCancelledBeforeInstalling() throws {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("datalayer-install-output-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let completedURL = fileManager.temporaryDirectory
            .appendingPathComponent("datalayer-install-completed-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let original = Data("existing output".utf8)
        try original.write(to: outputURL)
        try Data("completed replacement".utf8).write(to: completedURL)
        defer {
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.removeItem(at: completedURL)
        }

        XCTAssertThrowsError(try VideoExportSupport.installCompletedOutput(
            from: completedURL,
            to: outputURL,
            cancellationHandler: { true }
        )) { error in
            guard case OverlayVideoError.cancelled = error else {
                return XCTFail("Expected cancelled, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: outputURL), original)
        XCTAssertEqual(
            try Data(contentsOf: completedURL),
            Data("completed replacement".utf8)
        )
    }

    func testCompletedOutputReplacementFailureKeepsExistingFile() throws {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("datalayer-install-existing-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let completedURL = fileManager.temporaryDirectory
            .appendingPathComponent("datalayer-install-completed-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let original = Data("existing output".utf8)
        let completed = Data("completed replacement".utf8)
        try original.write(to: outputURL)
        try completed.write(to: completedURL)
        defer {
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.removeItem(at: completedURL)
        }

        XCTAssertThrowsError(try VideoExportSupport.installCompletedOutput(
            from: completedURL,
            to: outputURL,
            cancellationHandler: nil,
            replaceItem: { _, _ in throw CocoaError(.fileWriteNoPermission) }
        ))
        XCTAssertEqual(try Data(contentsOf: outputURL), original)
        XCTAssertEqual(try Data(contentsOf: completedURL), completed)
    }

    func testCompletedOutputReplacementRetriesCrossVolumeErrorOnDestinationVolume() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("output.mov")
        let completedURL = directory.appendingPathComponent("completed.mov")
        let original = Data("existing video".utf8)
        let completed = Data(repeating: 42, count: 2_000_000)
        try original.write(to: outputURL)
        try completed.write(to: completedURL)
        var attempts = 0
        var stagedURL: URL?
        var diagnostics: [VideoExportDiagnosticEvent] = []

        try VideoExportSupport.installCompletedOutput(
            from: completedURL, to: outputURL, cancellationHandler: nil,
            diagnosticsHandler: { diagnostics.append($0) },
            replaceItem: { target, source in
                attempts += 1
                XCTAssertEqual(try Data(contentsOf: target), original)
                if attempts == 1 {
                    throw NSError(domain: NSCocoaErrorDomain, code: 512,
                                  userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EXDEV))])
                }
                stagedURL = source
                XCTAssertNotEqual(source, completedURL)
                XCTAssertEqual(try Data(contentsOf: source), completed)
                XCTAssertEqual(try manager.attributesOfFileSystem(forPath: source.path)[.systemNumber] as? NSNumber,
                               try manager.attributesOfFileSystem(forPath: target.path)[.systemNumber] as? NSNumber)
                _ = try manager.replaceItemAt(target, withItemAt: source)
            }
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(try Data(contentsOf: outputURL), completed)
        XCTAssertFalse(manager.fileExists(atPath: completedURL.path))
        XCTAssertFalse(manager.fileExists(atPath: try XCTUnwrap(stagedURL).deletingLastPathComponent().path))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: directory.path), ["output.mov"])
        XCTAssertEqual(diagnostics.compactMap(\.operationStep), [.outputCheckCompleted, .outputReplace, .outputCopy, .outputReplace])
        XCTAssertFalse(diagnostics.contains { $0.phase == .failure })
    }

    func testCompletedOutputCrossVolumeRetryFailureKeepsExistingAndCompletedFiles() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("output.mov")
        let completedURL = directory.appendingPathComponent("completed.mov")
        let original = Data("existing video".utf8)
        let completed = Data("completed video".utf8)
        try original.write(to: outputURL)
        try completed.write(to: completedURL)
        var attempts = 0
        var stagedURL: URL?
        var diagnostics: [VideoExportDiagnosticEvent] = []

        XCTAssertThrowsError(try VideoExportSupport.installCompletedOutput(
            from: completedURL, to: outputURL, cancellationHandler: nil,
            diagnosticsHandler: { diagnostics.append($0) },
            replaceItem: { _, source in
                attempts += 1
                if attempts == 1 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EXDEV)) }
                stagedURL = source
                throw CocoaError(.fileWriteNoPermission)
            }
        )) { error in
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteNoPermission.rawValue)
        }

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(try Data(contentsOf: outputURL), original)
        XCTAssertEqual(try Data(contentsOf: completedURL), completed)
        XCTAssertFalse(manager.fileExists(atPath: try XCTUnwrap(stagedURL).deletingLastPathComponent().path))
        XCTAssertEqual(diagnostics.last?.operationStep, .outputReplace)
        XCTAssertEqual(diagnostics.last?.phase, .failure)
    }

    func testCompletedOutputCrossVolumeCopyCancellationKeepsExistingAndCompletedFiles() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("output.mov")
        let completedURL = directory.appendingPathComponent("completed.mov")
        let original = Data("existing video".utf8)
        let completed = Data("completed video".utf8)
        try original.write(to: outputURL)
        try completed.write(to: completedURL)
        var attempts = 0
        var cancelled = false

        XCTAssertThrowsError(try VideoExportSupport.installCompletedOutput(
            from: completedURL, to: outputURL, cancellationHandler: { cancelled },
            diagnosticsHandler: { if $0.operationStep == .outputCopy { cancelled = true } },
            replaceItem: { _, _ in
                attempts += 1
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EXDEV))
            }
        )) { error in
            guard case OverlayVideoError.cancelled = error else { return XCTFail("Expected cancellation, got \(error)") }
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(cancelled)
        XCTAssertEqual(try Data(contentsOf: outputURL), original)
        XCTAssertEqual(try Data(contentsOf: completedURL), completed)
    }

    func testCompletedOutputInstallationPreservesMissingDirectoryError() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let completedURL = directory.appendingPathComponent("completed.mov")
        let outputURL = directory.appendingPathComponent("missing/output.mov")
        let completed = Data("completed video".utf8)
        try completed.write(to: completedURL)
        var diagnostics: [VideoExportDiagnosticEvent] = []

        XCTAssertThrowsError(try VideoExportSupport.installCompletedOutput(
            from: completedURL, to: outputURL, cancellationHandler: nil,
            diagnosticsHandler: { diagnostics.append($0) }
        )) { error in
            let native = error as NSError
            XCTAssertEqual(native.domain, NSCocoaErrorDomain)
            let underlying = native.userInfo[NSUnderlyingErrorKey] as? NSError
            XCTAssertEqual(underlying?.domain, NSPOSIXErrorDomain)
            XCTAssertEqual(underlying?.code, Int(ENOENT))
        }
        XCTAssertEqual(try Data(contentsOf: completedURL), completed)
        XCTAssertFalse(manager.fileExists(atPath: outputURL.path))
        let failure = try XCTUnwrap(diagnostics.last)
        XCTAssertEqual(failure.phase, .failure)
        XCTAssertEqual(failure.operationStep, .outputCreateFile)
        XCTAssertEqual(failure.fileSystemHints?.sourceExists, true)
        XCTAssertEqual(failure.fileSystemHints?.parentExists, false)
        XCTAssertEqual(failure.fileSystemHints?.failurePathRole, .target)
        XCTAssertEqual(failure.fileSystemHints?.failureParentExists, false)
        XCTAssertEqual(diagnostics.compactMap(\.operationStep),
                       [.outputCheckCompleted, .outputMove, .outputCopy, .outputCreateFile])
    }

    func testCompletedOutputInstallationPreservesMissingSourceError() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("output.mov")
        let original = Data("existing video".utf8)
        try original.write(to: outputURL)
        var diagnostics: [VideoExportDiagnosticEvent] = []
        XCTAssertThrowsError(try VideoExportSupport.installCompletedOutput(
            from: directory.appendingPathComponent("missing.mov"),
            to: outputURL, cancellationHandler: nil, diagnosticsHandler: { diagnostics.append($0) }
        )) { error in
            let native = error as NSError
            XCTAssertEqual(native.domain, NSCocoaErrorDomain)
            let underlying = native.userInfo[NSUnderlyingErrorKey] as? NSError
            XCTAssertEqual(underlying?.domain, NSPOSIXErrorDomain)
            XCTAssertEqual(underlying?.code, Int(ENOENT))
        }
        XCTAssertEqual(try Data(contentsOf: outputURL), original)
        XCTAssertEqual(diagnostics.last?.operationStep, .outputCheckCompleted)
        XCTAssertEqual(diagnostics.last?.fileSystemHints?.sourceExists, false)
        XCTAssertEqual(diagnostics.last?.fileSystemHints?.targetExists, true)
        XCTAssertEqual(diagnostics.last?.fileSystemHints?.failurePathRole, .source)
    }

    func testWriterCancelsAfterRenderingBeginsWithoutInstallingOutput() {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-active-cancel-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let state = ActiveRenderCancellationState()
        let completed = expectation(description: "Transparent writer cancellation completes")
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3)
            ]),
            config: TransparentVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 1,
                duration: 3,
                codec: .proRes4444,
                progressHandler: { completedFrames, totalFrames in
                    state.recordProgress(completed: completedFrames, total: totalFrames)
                },
                cancellationHandler: { state.shouldCancel }
            )
        )

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try writer.write()
                state.recordCompletion(error: nil)
            } catch {
                state.recordCompletion(error: error)
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 5)
        XCTAssertTrue(state.didBeginRendering)
        guard let error = state.completionError else {
            return XCTFail("Expected active render cancellation")
        }
        guard case OverlayVideoError.cancelled = error else {
            return XCTFail("Expected cancelled, got \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testHEVCAlphaCancellationPreservesAnExistingOutput() throws {
        guard OverlayHardwareProfile.current.canUseHardwareEncoder(for: .hevcAlpha) else {
            throw XCTSkip("This Mac does not list a hardware HEVC-with-alpha encoder.")
        }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-alpha-\(UUID().uuidString).mov")
        let original = Data("existing export".utf8)
        try original.write(to: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let state = ActiveRenderCancellationState()
        let writer = TransparentVideoWriter(outputURL: outputURL,
            series: TelemetrySeries(samples: [TelemetrySample(elapsed: 0, speedMetersPerSecond: 3)]),
            config: TransparentVideoWriterConfig(width: 1920, height: 1080, framesPerSecond: 30, duration: 10,
                codec: .hevcAlpha, progressHandler: state.recordProgress, cancellationHandler: { state.shouldCancel }))
        do {
            try writer.write()
            XCTFail("Expected cancellation after rendering starts")
        } catch let error as OverlayVideoError where error.isUnavailableHEVCAlphaTestEncoder {
            throw XCTSkip("HEVC-with-alpha encoder is unavailable: \(error.description)")
        } catch {
            guard case OverlayVideoError.cancelled = error else { return XCTFail("Expected cancellation, got \(error)") }
        }
        XCTAssertTrue(state.didBeginRendering)
        XCTAssertEqual(try Data(contentsOf: outputURL), original)
    }

    func testWriterRendersTinyHEVCAlphaOutputWhenEncoderIsAvailable() async throws {
        guard OverlayHardwareProfile.current.canUseHardwareEncoder(for: .hevcAlpha) else {
            throw XCTSkip("This Mac does not list a hardware HEVC-with-alpha encoder.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-tiny-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        var diagnostics: [VideoExportDiagnosticEvent] = []
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
                TelemetrySample(elapsed: 1, distanceMeters: 3, speedMetersPerSecond: 3)
            ]),
            config: TransparentVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 1,
                duration: 1,
                diagnosticsHandler: { diagnostics.append($0) }
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableHEVCAlphaTestEncoder {
            throw XCTSkip("HEVC-with-alpha encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let timeScale = try await tracks[0].load(.naturalTimeScale)
        XCTAssertEqual(timeScale, TransparentVideoFrameTiming.preferredTimescale)
        XCTAssertTrue(diagnostics.contains { $0.stage == .prepareWriter && $0.phase == .begin })
        XCTAssertTrue(diagnostics.contains { $0.stage == .awaitReady && $0.phase == .begin })
        XCTAssertTrue(diagnostics.contains { $0.stage == .appendFrame && $0.phase == .begin })
        XCTAssertTrue(diagnostics.contains { $0.stage == .finishInput && $0.phase == .end })
        XCTAssertTrue(diagnostics.contains { $0.stage == .finishWriter && $0.phase == .end })
        XCTAssertTrue(diagnostics.contains { $0.stage == .installOutput && $0.phase == .end })
        XCTAssertEqual(diagnostics.last?.stage, .exportCompleted)
    }

    func testWriterPreservesRequested4KResolution() async throws {
        guard OverlayHardwareProfile.current.canUseHardwareEncoder(for: .hevcAlpha) else {
            throw XCTSkip("This Mac does not list a hardware HEVC-with-alpha encoder.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-4k-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3)
            ]),
            config: TransparentVideoWriterConfig(
                width: 3_840,
                height: 2_160,
                framesPerSecond: 1,
                duration: 1
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableHEVCAlphaTestEncoder {
            throw XCTSkip("HEVC-with-alpha encoder is unavailable on this Mac: \(error.description)")
        }

        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let naturalSize = try await tracks[0].load(.naturalSize)
        XCTAssertEqual(Int(naturalSize.width.rounded()), 3_840)
        XCTAssertEqual(Int(naturalSize.height.rounded()), 2_160)
    }

    func testWriterKeepsNTSCTrackTimeScaleWhenSourceRateIsExact() async throws {
        guard OverlayHardwareProfile.current.canUseHardwareEncoder(for: .hevcAlpha) else {
            throw XCTSkip("This Mac does not list a hardware HEVC-with-alpha encoder.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-ntsc-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let fps = 30_000.0 / 1_001.0
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0)
            ]),
            config: TransparentVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: fps,
                duration: Double(2 * 1_001) / 30_000
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableHEVCAlphaTestEncoder {
            throw XCTSkip("HEVC-with-alpha encoder is unavailable on this Mac: \(error.description)")
        }

        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let timeScale = try await tracks[0].load(.naturalTimeScale)
        let duration = try await tracks[0].load(.timeRange).duration
        XCTAssertEqual(timeScale, 30_000)
        XCTAssertEqual(CMTimeGetSeconds(duration), Double(2 * 1_001) / 30_000, accuracy: 0.000000001)
    }

    func testHEVCAlphaKeepsEmptyPixelsTransparent() async throws {
        guard OverlayHardwareProfile.current.canUseHardwareEncoder(for: .hevcAlpha) else {
            throw XCTSkip("This Mac does not list a hardware HEVC-with-alpha encoder.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-alpha-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        var element = OverlayElement.defaultElement(kind: .pace)
        element.frame = OverlayComponentFrame(x: 0.45, y: 0.45, scale: 1)
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3)
            ]),
            config: TransparentVideoWriterConfig(
                width: 256,
                height: 256,
                framesPerSecond: 1,
                duration: 1,
                overlayLayout: OverlayLayout(elements: [element])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableHEVCAlphaTestEncoder {
            throw XCTSkip("HEVC-with-alpha encoder is unavailable on this Mac: \(error.description)")
        }

        let pixel = try await decodedMaximumPixel(in: CGRect(x: 0, y: 0, width: 48, height: 48), from: outputURL)
        XCTAssertLessThanOrEqual(pixel.alpha, 1)
        XCTAssertLessThanOrEqual(pixel.red, 1)
        XCTAssertLessThanOrEqual(pixel.green, 1)
        XCTAssertLessThanOrEqual(pixel.blue, 1)
    }

    private func assertWriterRejectsInvalidConfiguration(
        config: TransparentVideoWriterConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-invalid-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: []),
            config: config
        )

        XCTAssertThrowsError(try writer.write(), file: file, line: line) { error in
            guard case OverlayVideoError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)", file: file, line: line)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path), file: file, line: line)
    }

    private func validTinyConfig() -> TransparentVideoWriterConfig {
        TransparentVideoWriterConfig(
            width: 2,
            height: 2,
            framesPerSecond: 1,
            duration: 1
        )
    }

    private struct DecodedPixel {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8
    }

    private func decodedMaximumPixel(in rect: CGRect, from url: URL) async throws -> DecodedPixel {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: try XCTUnwrap(tracks.first),
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let sampleBuffer = try XCTUnwrap(output.copyNextSampleBuffer())
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)
        var maximum = DecodedPixel(red: 0, green: 0, blue: 0, alpha: 0)
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let offset = y * bytesPerRow + x * 4
                maximum.red = max(maximum.red, bytes[offset + 2])
                maximum.green = max(maximum.green, bytes[offset + 1])
                maximum.blue = max(maximum.blue, bytes[offset])
                maximum.alpha = max(maximum.alpha, bytes[offset + 3])
            }
        }
        return maximum
    }
}

private final class ActiveRenderCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationRequested = false
    private var renderingBegan = false
    private var error: Error?

    var shouldCancel: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    var didBeginRendering: Bool {
        lock.lock()
        defer { lock.unlock() }
        return renderingBegan
    }

    var completionError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }

    func recordProgress(completed: Int, total: Int) {
        guard completed > 0, completed < total else { return }
        lock.lock()
        renderingBegan = true
        cancellationRequested = true
        lock.unlock()
    }

    func recordCompletion(error: Error?) {
        lock.lock()
        self.error = error
        lock.unlock()
    }
}

private extension OverlayVideoError {
    var isUnavailableHEVCAlphaTestEncoder: Bool {
        switch self {
        case .unsupportedEncoder, .cannotStartWriter:
            return true
        case let .writerFailed(message, _):
            return message.localizedCaseInsensitiveContains("encoder") || message.contains("-12903")
        case .unreadableVideo,
             .cannotCreatePixelBuffer,
             .cannotCreateBitmapContext,
             .invalidConfiguration,
             .cancelled:
            return false
        }
    }
}
