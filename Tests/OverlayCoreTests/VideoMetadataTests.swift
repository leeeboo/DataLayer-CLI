import XCTest
@testable import OverlayCore

final class VideoMetadataTests: XCTestCase {
    func testInvalidVideoFailureIncludesLocalHintsAndOriginalCause() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let bytes = Data("not a movie".utf8)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await VideoMetadata.loadAsync(from: url)
            XCTFail("Invalid media must fail")
        } catch {
            let error = error as NSError
            let media = try XCTUnwrap(error.userInfo["video_metadata"] as? [String: Any])
            XCTAssertEqual(media["import_phase"] as? String, "duration")
            XCTAssertEqual(media["source_file_bytes"] as? Int, bytes.count)
            XCTAssertEqual(media["source_exists"] as? Bool, true)
            XCTAssertEqual(media["source_readable"] as? Bool, true)
            XCTAssertEqual(media["container_hint"] as? String, "unrecognized")
            XCTAssertNotEqual(error.code, 0)
            XCTAssertFalse(String(describing: media).contains(url.path))
            XCTAssertFalse(String(describing: media).contains("not a movie"))
        }
    }

    func testMissingVideoFailureDistinguishesMissingFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        do {
            _ = try await VideoMetadata.loadAsync(from: url)
            XCTFail("Missing media must fail")
        } catch {
            let media = try XCTUnwrap((error as NSError).userInfo["video_metadata"] as? [String: Any])
            XCTAssertEqual(media["source_exists"] as? Bool, false)
            XCTAssertEqual(media["source_readable"] as? Bool, false)
            XCTAssertEqual(media["container_hint"] as? String, "not_probed")
        }
    }

    private let containerDate = Date(timeIntervalSince1970: 1_752_000_000)
    private let recordingDate = Date(timeIntervalSince1970: 1_751_000_000)

    func testExplicitRecordingMetadataWinsOverEditorSignature() {
        let resolved = VideoMetadata.resolveCreationDate(
            containerCreationDate: containerDate,
            explicitRecordingDate: recordingDate,
            writingApplication: "Blackmagic Design DaVinci Resolve Studio"
        )

        XCTAssertEqual(resolved.date, recordingDate)
        XCTAssertEqual(resolved.source, .recordingMetadata)
    }

    func testDaVinciContainerDateIsRejectedWithoutRecordingMetadata() {
        let resolved = VideoMetadata.resolveCreationDate(
            containerCreationDate: containerDate,
            explicitRecordingDate: nil,
            writingApplication: "Blackmagic Design DaVinci Resolve Studio"
        )

        XCTAssertNil(resolved.date)
        XCTAssertEqual(resolved.source, .untrustedExport)
    }

    func testOrdinaryContainerDateRemainsAvailableAsFallback() {
        let resolved = VideoMetadata.resolveCreationDate(
            containerCreationDate: containerDate,
            explicitRecordingDate: nil,
            writingApplication: nil
        )

        XCTAssertEqual(resolved.date, containerDate)
        XCTAssertEqual(resolved.source, .containerMetadata)
    }
}
