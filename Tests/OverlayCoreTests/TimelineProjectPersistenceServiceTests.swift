import Foundation
import OverlayCore
import XCTest

final class TimelineProjectPersistenceServiceTests: XCTestCase {
    func testSavingUsesCurrentSchemaBookmarkAndRelativeMediaPath() throws {
        let projectURL = URL(fileURLWithPath: "/Projects/Race/race.dlsproj")
        let mediaURL = URL(fileURLWithPath: "/Projects/Race/Media/run.gpx")
        let bookmark = Data([1, 2, 3])
        let project = makeProject(
            asset: MediaAsset(
                id: "activity",
                kind: .activity,
                url: mediaURL,
                displayName: "run.gpx",
                duration: 60
            ),
            schemaVersion: 1
        )

        let data = try TimelineProjectPersistenceService.jsonData(
            for: project,
            relativeTo: projectURL,
            bookmarkDataProvider: { $0 == mediaURL ? bookmark : nil }
        )
        let saved = try JSONDecoder().decode(TimelineProject.self, from: data)

        XCTAssertEqual(saved.schemaVersion, TimelineProject.currentSchemaVersion)
        XCTAssertEqual(saved.assets[0].bookmarkData, bookmark)
        XCTAssertEqual(saved.assets[0].relativePath, "Media/run.gpx")
    }

    func testLoadingPrefersReadableBookmarkThenOriginalThenRelativeURL() throws {
        let projectURL = URL(fileURLWithPath: "/Projects/Race/race.dlsproj")
        let originalURL = URL(fileURLWithPath: "/Missing/run.gpx")
        let bookmarkURL = URL(fileURLWithPath: "/Bookmark/run.gpx")
        let relativeURL = URL(fileURLWithPath: "/Projects/Race/Media/run.gpx")
        let bookmark = Data([4, 5, 6])
        let asset = MediaAsset(
            id: "activity",
            kind: .activity,
            url: originalURL,
            displayName: "run.gpx",
            duration: 60,
            bookmarkData: bookmark,
            relativePath: "Media/run.gpx"
        )
        let project = makeProject(asset: asset)

        var readable = Set([bookmarkURL])
        var resolved = TimelineProjectPersistenceService.resolvedProject(
            project,
            relativeTo: projectURL,
            bookmarkURLResolver: { $0 == bookmark ? bookmarkURL : nil },
            isReadableURL: { readable.contains($0) }
        )
        XCTAssertEqual(resolved.assets[0].url, bookmarkURL)

        readable = [originalURL]
        resolved = TimelineProjectPersistenceService.resolvedProject(
            project,
            relativeTo: projectURL,
            bookmarkURLResolver: { $0 == bookmark ? bookmarkURL : nil },
            isReadableURL: { readable.contains($0) }
        )
        XCTAssertEqual(resolved.assets[0].url, originalURL)

        readable = [relativeURL]
        resolved = TimelineProjectPersistenceService.resolvedProject(
            project,
            relativeTo: projectURL,
            bookmarkURLResolver: { $0 == bookmark ? bookmarkURL : nil },
            isReadableURL: { readable.contains($0) }
        )
        XCTAssertEqual(resolved.assets[0].url, relativeURL)
    }

    func testLoadingKeepsOfflineAssetIdentityAndURL() throws {
        let originalURL = URL(fileURLWithPath: "/Missing/run.gpx")
        let project = makeProject(
            asset: MediaAsset(
                id: "stable.activity",
                kind: .activity,
                url: originalURL,
                displayName: "run.gpx",
                duration: 60,
                relativePath: "Media/run.gpx"
            )
        )
        let data = try JSONEncoder().encode(project)

        let loaded = try TimelineProjectPersistenceService.project(
            from: data,
            relativeTo: URL(fileURLWithPath: "/Elsewhere/race.dlsproj"),
            isReadableURL: { _ in false }
        )

        XCTAssertEqual(loaded.assets[0].id, "stable.activity")
        XCTAssertEqual(loaded.assets[0].url, originalURL)
    }

    func testSavingClearsStaleRelativePathAfterRelinkOutsideProjectDirectory() {
        let projectURL = URL(fileURLWithPath: "/Projects/Race/race.dlsproj")
        let relocatedURL = URL(fileURLWithPath: "/Replacement/run.gpx")
        let project = makeProject(
            asset: MediaAsset(
                id: "activity",
                kind: .activity,
                url: relocatedURL,
                displayName: "run.gpx",
                duration: 60,
                relativePath: "Media/run.gpx"
            )
        )

        let saved = TimelineProjectPersistenceService.projectForSaving(project, relativeTo: projectURL)

        XCTAssertNil(saved.assets[0].relativePath)
    }

    private func makeProject(
        asset: MediaAsset,
        schemaVersion: Int = TimelineProject.currentSchemaVersion
    ) -> TimelineProject {
        TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [asset],
            schemaVersion: schemaVersion
        )
    }
}
