@testable import OverlayCore
import XCTest

final class VideoExportDiagnosticEventTests: XCTestCase {
    func testSchemaV1CarriesOnlyRedactedOperationalFields() {
        let event = VideoExportDiagnosticEvent(
            stage: .readSource,
            phase: .update,
            frameIndex: 4,
            totalFrames: 60,
            readerStatus: .reading,
            writerStatus: .writing,
            exportStatus: .exporting,
            exportProgress: 0.5,
            inputReady: true,
            errorDomain: "AVFoundationErrorDomain",
            errorCode: -11800,
            sourceFourCC: 0x61766331,
            sourceSize: .init(width: 1_920, height: 1_080),
            sourceFramesPerSecond: 29.97,
            sourceHasAudio: true,
            preparationStep: .inspectVideoSource,
            sourceIndex: 2,
            sourceCount: 10,
            sourceFileSizeBytes: 1_234_567,
            sourceVideoTrackCount: 1,
            sourceAudioTrackCount: 2,
            mediaTrackIndex: 1,
            mediaTrackCount: 2,
            timelineStartSeconds: 12.5,
            timelineDurationSeconds: 4.25
        )

        XCTAssertEqual(event.schemaVersion, 1)
        XCTAssertEqual(event.stage, .readSource)
        XCTAssertEqual(event.phase, .update)
        XCTAssertEqual(event.sourceSize, .init(width: 1_920, height: 1_080))

        let labels = Set(Mirror(reflecting: event).children.compactMap(\.label))
        XCTAssertEqual(labels, [
            "schemaVersion", "stage", "phase", "frameIndex", "totalFrames",
            "readerStatus", "writerStatus", "exportStatus", "exportProgress", "inputReady",
            "errorDomain", "errorCode", "sourceFourCC", "sourceSize",
            "sourceFramesPerSecond", "sourceHasAudio", "preparationStep",
            "sourceIndex", "sourceCount", "sourceFileSizeBytes",
            "sourceVideoTrackCount", "sourceAudioTrackCount", "mediaTrackIndex",
            "mediaTrackCount", "timelineStartSeconds", "timelineDurationSeconds",
            "operationStep", "decodeAttempt", "decodeTimeoutSeconds", "decodeIdleSeconds",
            "decodeProducedSample", "sourceTimeSeconds", "fileSystemHints"
        ])
        for forbidden in [
            "path", "url", "name", "sourceDescription", "localizedDescription",
            "userInfo", "telemetry", "clipID", "clipId"
        ] {
            XCTAssertFalse(labels.contains(forbidden), "Diagnostic schema must not expose \(forbidden).")
        }
    }

    func testOptionalCheckpointsRoundTripAndLegacyEventsRemainReadable() throws {
        let event = VideoExportDiagnosticEvent(stage: .installOutput, phase: .failure,
            operationStep: .outputCopy, decodeTimeoutSeconds: 8, decodeIdleSeconds: 8.1,
            decodeProducedSample: false, sourceTimeSeconds: 12.5,
            fileSystemHints: .init(sourceExists: true, parentExists: false,
                failurePathRole: .target, failurePathExists: false, failureParentExists: false))
        let encoded = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(VideoExportDiagnosticEvent.self, from: encoded), event)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["operationStep", "decodeAttempt", "decodeTimeoutSeconds", "decodeIdleSeconds", "decodeProducedSample", "sourceTimeSeconds", "fileSystemHints"] { legacy.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(VideoExportDiagnosticEvent.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored.stage, .installOutput)
        XCTAssertNil(restored.operationStep)
        XCTAssertNil(restored.decodeAttempt)
        XCTAssertNil(restored.fileSystemHints)
        XCTAssertNil(restored.decodeTimeoutSeconds)
        XCTAssertNil(restored.decodeIdleSeconds)
        XCTAssertNil(restored.decodeProducedSample)
        XCTAssertNil(restored.sourceTimeSeconds)
        XCTAssertNil(restored.exportProgress)
    }

    func testFailurePathsAreClassifiedWithoutPersistingPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("private-\(UUID())")
        let source = root.appendingPathComponent("private-source.mov")
        let target = root.appendingPathComponent("missing/private-output.mov")
        for (url, role) in [(source, VideoExportFileSystemHints.FailurePathRole.source),
                            (target, .target), (target.deletingLastPathComponent(), .parent),
                            (target.appendingPathComponent("private-child"), .targetChild),
                            (root.appendingPathComponent("other"), .other)] {
            let error = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 2,
                    userInfo: [NSFilePathErrorKey: url.path])
            ])
            let hints = VideoExportFileSystemHints.capture(sourceURL: source, targetURL: target, error: error)
            XCTAssertEqual(hints.failurePathRole, role)
            XCTAssertEqual(hints.failurePathExists, role == .other ? nil : false)
            XCTAssertEqual(hints.failureParentExists, role == .other ? nil : false)
            XCTAssertFalse(String(decoding: try JSONEncoder().encode(hints), as: UTF8.self).contains("private"))
        }
        #if os(Windows)
        let windowsError = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSFilePathErrorKey: target.path.uppercased().replacingOccurrences(of: "/", with: "\\")])
        XCTAssertEqual(VideoExportFileSystemHints.capture(sourceURL: source, targetURL: target, error: windowsError).failurePathRole, .target)
        #endif
    }

    func testAllStandardCompositedStagesAreRepresentedInSchemaV1() {
        XCTAssertEqual(Set(VideoExportDiagnosticEvent.Stage.allCases), [
            .prepareTimeline, .prepareReader, .prepareWriter, .awaitReady, .readSource, .readAudio, .appendAudio,
            .renderOverlay, .ciComposite, .appendFrame, .finishInput, .finishWriter,
            .audioMuxPassthrough, .audioMuxReencode, .installOutput, .exportCompleted,
            .exportFailed
        ])
        XCTAssertEqual(Set(VideoExportDiagnosticEvent.Phase.allCases), [.begin, .end, .update, .failure])
        XCTAssertEqual(Set(VideoExportDiagnosticEvent.PreparationStep.allCases), [
            .startExportTask, .acquireSecurityScopes, .validateProject, .collectVideoClips,
            .prepareVideoSegments, .inspectVideoSource, .resolveVideoRange,
            .resolveVideoTransform, .prepareAudioComposition, .inspectAudioSource,
            .insertAudioTrack, .prepareOverlays, .prepareRenderResources,
            .createCompositedWriter, .initializeCompositedWriter
        ])
    }
}
