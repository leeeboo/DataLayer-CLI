import Foundation

/// Platform-neutral `.dlsproj` encoding and media URL resolution.
///
/// Security-scoped bookmark creation and resolution stay in each platform session model and are
/// injected as closures, so the shared layer does not depend on AppKit or UIKit.
public enum TimelineProjectPersistenceService {
    public static func jsonData(
        for project: TimelineProject,
        relativeTo projectURL: URL? = nil,
        bookmarkDataProvider: (URL) -> Data? = { _ in nil }
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            projectForSaving(
                project,
                relativeTo: projectURL,
                bookmarkDataProvider: bookmarkDataProvider
            )
        )
    }

    public static func project(
        from data: Data,
        relativeTo projectURL: URL? = nil,
        bookmarkURLResolver: (Data) -> URL? = { _ in nil },
        isReadableURL: (URL) -> Bool = {
            FileManager.default.isReadableFile(atPath: $0.path)
        }
    ) throws -> TimelineProject {
        let decoded = try JSONDecoder().decode(TimelineProject.self, from: data)
        return resolvedProject(
            decoded,
            relativeTo: projectURL,
            bookmarkURLResolver: bookmarkURLResolver,
            isReadableURL: isReadableURL
        )
    }

    public static func projectForSaving(
        _ project: TimelineProject,
        relativeTo projectURL: URL? = nil,
        bookmarkDataProvider: (URL) -> Data? = { _ in nil }
    ) -> TimelineProject {
        var saved = project
        saved.schemaVersion = TimelineProject.currentSchemaVersion
        saved.assets = project.assets.map { asset in
            var updated = asset
            updated.bookmarkData = bookmarkDataProvider(asset.url) ?? asset.bookmarkData
            if let projectURL {
                updated.relativePath = relativeMediaPath(for: asset.url, projectURL: projectURL)
            }
            return updated
        }
        return saved
    }

    public static func resolvedProject(
        _ project: TimelineProject,
        relativeTo projectURL: URL? = nil,
        bookmarkURLResolver: (Data) -> URL? = { _ in nil },
        isReadableURL: (URL) -> Bool = {
            FileManager.default.isReadableFile(atPath: $0.path)
        }
    ) -> TimelineProject {
        var resolved = project
        resolved.assets = project.assets.map { asset in
            var candidates: [URL] = []
            if let bookmarkData = asset.bookmarkData,
               let bookmarkURL = bookmarkURLResolver(bookmarkData) {
                candidates.append(bookmarkURL)
            }
            candidates.append(asset.url)
            if let projectURL,
               let relativePath = asset.relativePath,
               !relativePath.isEmpty {
                candidates.append(
                    projectURL.deletingLastPathComponent()
                        .appendingPathComponent(relativePath)
                        .standardizedFileURL
                )
            }
            guard let resolvedURL = candidates.first(where: isReadableURL) else { return asset }
            var updated = asset
            updated.url = resolvedURL
            return updated
        }
        return resolved
    }

    public static func relativeMediaPath(for mediaURL: URL, projectURL: URL) -> String? {
        #if os(Windows)
        let directory = projectURL.deletingLastPathComponent().standardizedFileURL.pathComponents
        let media = mediaURL.standardizedFileURL.pathComponents
        guard media.count > directory.count,
              zip(directory, media).allSatisfy({ $0.caseInsensitiveCompare($1) == .orderedSame }) else { return nil }
        return media.dropFirst(directory.count).joined(separator: "/")
        #else
        let directoryPath = projectURL.deletingLastPathComponent().standardizedFileURL.path
        let mediaPath = mediaURL.standardizedFileURL.path
        let prefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        guard mediaPath.hasPrefix(prefix) else { return nil }
        let relative = String(mediaPath.dropFirst(prefix.count))
        return relative.isEmpty ? nil : relative
        #endif
    }
}
