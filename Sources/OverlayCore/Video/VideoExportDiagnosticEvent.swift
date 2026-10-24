import Foundation

/// A redacted, versioned progress event emitted while producing a standard composited video.
///
/// This deliberately carries operational state only. It must not gain file paths, URLs, asset
/// names, localized error text, error user-info, telemetry, or timeline identifiers.
public struct VideoExportDiagnosticEvent: Codable, Sendable, Equatable {
    public enum Stage: String, Codable, Sendable, CaseIterable {
        case prepareTimeline
        case prepareReader
        case prepareWriter
        case awaitReady
        case readSource
        case readAudio
        case appendAudio
        case renderOverlay
        case ciComposite
        case appendFrame
        case finishInput
        case finishWriter
        case audioMuxPassthrough
        case audioMuxReencode
        case installOutput
        case exportCompleted
        case exportFailed
    }

    public enum Phase: String, Codable, Sendable, CaseIterable {
        case begin
        case end
        case update
        case failure
    }

    /// Code-owned checkpoints inside existing stages, emitted only at attempt/install boundaries.
    public enum OperationStep: String, Codable, Sendable, CaseIterable {
        case decoderQueued
        case decoderCreateReader
        case decoderStartReader
        case decoderCopySample
        case decoderSampleReady
        case outputCheckCompleted
        case outputReplace
        case outputMove
        case outputCopy
        case outputCreateFile
        case outputOpenSource
        case outputOpenTarget
        case outputReadSource
        case outputWriteTarget
        case outputSynchronize
    }

    /// Privacy-safe checkpoints inside timeline preparation. These values identify
    /// code paths only; source identity is represented by a one-based ordinal.
    public enum PreparationStep: String, Codable, Sendable, CaseIterable {
        case startExportTask
        case acquireSecurityScopes
        case validateProject
        case collectVideoClips
        case prepareVideoSegments
        case inspectVideoSource
        case resolveVideoRange
        case resolveVideoTransform
        case prepareAudioComposition
        case inspectAudioSource
        case insertAudioTrack
        case prepareOverlays
        case prepareRenderResources
        case createCompositedWriter
        case initializeCompositedWriter
    }

    public enum ReaderStatus: String, Codable, Sendable, Equatable {
        case unknown
        case reading
        case completed
        case failed
        case cancelled
    }

    public enum WriterStatus: String, Codable, Sendable, Equatable {
        case unknown
        case writing
        case completed
        case failed
        case cancelled
    }

    public enum ExportStatus: String, Codable, Sendable, Equatable {
        case unknown
        case waiting
        case exporting
        case completed
        case failed
        case cancelled
    }

    public struct SourceSize: Codable, Sendable, Equatable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// Increment this only when the event schema changes incompatibly.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let stage: Stage
    public let phase: Phase
    public let frameIndex: Int?
    public let totalFrames: Int?
    public let readerStatus: ReaderStatus?
    public let writerStatus: WriterStatus?
    public let exportStatus: ExportStatus?
    public let exportProgress: Double?
    public let inputReady: Bool?
    public let errorDomain: String?
    public let errorCode: Int?
    public let sourceFourCC: UInt32?
    public let sourceSize: SourceSize?
    public let sourceFramesPerSecond: Double?
    public let sourceHasAudio: Bool?
    public let preparationStep: PreparationStep?
    /// One-based ordinal within the enabled clips being prepared for export.
    public let sourceIndex: Int?
    public let sourceCount: Int?
    public let sourceFileSizeBytes: Int64?
    public let sourceVideoTrackCount: Int?
    public let sourceAudioTrackCount: Int?
    public let mediaTrackIndex: Int?
    public let mediaTrackCount: Int?
    public let timelineStartSeconds: Double?
    public let timelineDurationSeconds: Double?
    public let operationStep: OperationStep?
    public let decodeAttempt: Int?
    public let decodeTimeoutSeconds: Double?
    public let decodeIdleSeconds: Double?
    public let decodeProducedSample: Bool?
    public let sourceTimeSeconds: Double?
    public let fileSystemHints: VideoExportFileSystemHints?

    public init(
        stage: Stage,
        phase: Phase,
        frameIndex: Int? = nil,
        totalFrames: Int? = nil,
        readerStatus: ReaderStatus? = nil,
        writerStatus: WriterStatus? = nil,
        exportStatus: ExportStatus? = nil,
        exportProgress: Double? = nil,
        inputReady: Bool? = nil,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        sourceFourCC: UInt32? = nil,
        sourceSize: SourceSize? = nil,
        sourceFramesPerSecond: Double? = nil,
        sourceHasAudio: Bool? = nil,
        preparationStep: PreparationStep? = nil,
        sourceIndex: Int? = nil,
        sourceCount: Int? = nil,
        sourceFileSizeBytes: Int64? = nil,
        sourceVideoTrackCount: Int? = nil,
        sourceAudioTrackCount: Int? = nil,
        mediaTrackIndex: Int? = nil,
        mediaTrackCount: Int? = nil,
        timelineStartSeconds: Double? = nil,
        timelineDurationSeconds: Double? = nil,
        operationStep: OperationStep? = nil,
        decodeAttempt: Int? = nil,
        decodeTimeoutSeconds: Double? = nil,
        decodeIdleSeconds: Double? = nil,
        decodeProducedSample: Bool? = nil,
        sourceTimeSeconds: Double? = nil,
        fileSystemHints: VideoExportFileSystemHints? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.stage = stage
        self.phase = phase
        self.frameIndex = frameIndex
        self.totalFrames = totalFrames
        self.readerStatus = readerStatus
        self.writerStatus = writerStatus
        self.exportStatus = exportStatus
        self.exportProgress = exportProgress
        self.inputReady = inputReady
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.sourceFourCC = sourceFourCC
        self.sourceSize = sourceSize
        self.sourceFramesPerSecond = sourceFramesPerSecond
        self.sourceHasAudio = sourceHasAudio
        self.preparationStep = preparationStep
        self.sourceIndex = sourceIndex
        self.sourceCount = sourceCount
        self.sourceFileSizeBytes = sourceFileSizeBytes
        self.sourceVideoTrackCount = sourceVideoTrackCount
        self.sourceAudioTrackCount = sourceAudioTrackCount
        self.mediaTrackIndex = mediaTrackIndex
        self.mediaTrackCount = mediaTrackCount
        self.timelineStartSeconds = timelineStartSeconds
        self.timelineDurationSeconds = timelineDurationSeconds
        self.operationStep = operationStep
        self.decodeAttempt = decodeAttempt
        self.decodeTimeoutSeconds = decodeTimeoutSeconds
        self.decodeIdleSeconds = decodeIdleSeconds
        self.decodeProducedSample = decodeProducedSample
        self.sourceTimeSeconds = sourceTimeSeconds
        self.fileSystemHints = fileSystemHints
    }
}

/// File attributes are hints only; they do not prove sandbox authorization or a successful write.
public struct VideoExportFileSystemHints: Codable, Sendable, Equatable {
    public enum FailurePathRole: String, Codable, Sendable {
        case source, target, parent, targetChild, other
    }

    public let sourceExists: Bool?
    public let sourceReadable: Bool?
    public let targetExists: Bool?
    public let targetDirectory: Bool?
    public let targetWritable: Bool?
    public let parentExists: Bool?
    public let parentWritable: Bool?
    public let availableCapacityBytes: Int64?
    public let volumeLocal: Bool?
    public let volumeRemovable: Bool?
    public let volumeReadOnly: Bool?
    public let failurePathRole: FailurePathRole?
    public let failurePathExists: Bool?
    public let failureParentExists: Bool?

    public init(sourceExists: Bool? = nil, sourceReadable: Bool? = nil,
                targetExists: Bool? = nil, targetDirectory: Bool? = nil, targetWritable: Bool? = nil,
                parentExists: Bool? = nil, parentWritable: Bool? = nil, availableCapacityBytes: Int64? = nil,
                volumeLocal: Bool? = nil, volumeRemovable: Bool? = nil, volumeReadOnly: Bool? = nil,
                failurePathRole: FailurePathRole? = nil, failurePathExists: Bool? = nil,
                failureParentExists: Bool? = nil) {
        self.sourceExists = sourceExists
        self.sourceReadable = sourceReadable
        self.targetExists = targetExists
        self.targetDirectory = targetDirectory
        self.targetWritable = targetWritable
        self.parentExists = parentExists
        self.parentWritable = parentWritable
        self.availableCapacityBytes = availableCapacityBytes
        self.volumeLocal = volumeLocal
        self.volumeRemovable = volumeRemovable
        self.volumeReadOnly = volumeReadOnly
        self.failurePathRole = failurePathRole
        self.failurePathExists = failurePathExists
        self.failureParentExists = failureParentExists
    }

    public static func capture(sourceURL: URL? = nil, targetURL: URL, error: Error? = nil) -> Self {
        let manager = FileManager.default
        let parent = targetURL.deletingLastPathComponent()
        var directory = ObjCBool(false)
        let exists = manager.fileExists(atPath: targetURL.path, isDirectory: &directory)
        let volumeURL = exists && directory.boolValue ? targetURL : parent
        let volume = try? volumeURL.resourceValues(forKeys: [
            .volumeAvailableCapacityKey, .volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsReadOnlyKey
        ])
        // Inspect native error paths locally; persist only their relation to the operation.
        var failureURL: URL?
        var current = error.map { $0 as NSError }
        var seen = Set<ObjectIdentifier>()
        while let value = current, seen.count < 5, seen.insert(ObjectIdentifier(value)).inserted {
            if let path = value.userInfo[NSFilePathErrorKey] as? String, Self.isAbsoluteFilePath(path) {
                failureURL = URL(fileURLWithPath: path).standardizedFileURL
                break
            }
            if let url = value.userInfo[NSURLErrorKey] as? URL, url.isFileURL {
                failureURL = url.standardizedFileURL
                break
            }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let role: FailurePathRole? = failureURL.map { url in
            let path = Self.comparisonPath(url)
            let targetPath = Self.comparisonPath(targetURL)
            if path == sourceURL.map(Self.comparisonPath) { return .source }
            if path == targetPath { return .target }
            if path == Self.comparisonPath(parent) { return .parent }
            if targetPath == "/" || path.hasPrefix(targetPath + "/") { return .targetChild }
            return .other
        }
        return Self(
            sourceExists: sourceURL.map { manager.fileExists(atPath: $0.path) },
            sourceReadable: sourceURL.map { manager.isReadableFile(atPath: $0.path) },
            targetExists: exists, targetDirectory: directory.boolValue,
            targetWritable: manager.isWritableFile(atPath: targetURL.path),
            parentExists: manager.fileExists(atPath: parent.path),
            parentWritable: manager.isWritableFile(atPath: parent.path),
            availableCapacityBytes: volume?.volumeAvailableCapacity.map(Int64.init),
            volumeLocal: volume?.volumeIsLocal, volumeRemovable: volume?.volumeIsRemovable,
            volumeReadOnly: volume?.volumeIsReadOnly,
            failurePathRole: role,
            failurePathExists: failureURL.flatMap { role == .other ? nil : manager.fileExists(atPath: $0.path) },
            failureParentExists: failureURL.flatMap { role == .other ? nil : manager.fileExists(atPath: $0.deletingLastPathComponent().path) }
        )
    }

    private static func isAbsoluteFilePath(_ path: String) -> Bool {
        #if os(Windows)
        return path.hasPrefix("/") || path.hasPrefix("\\\\")
            || path.range(of: #"^[A-Za-z]:[/\\]"#, options: .regularExpression) != nil
        #else
        return path.hasPrefix("/")
        #endif
    }

    private static func comparisonPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        #if os(Windows)
        return path.replacingOccurrences(of: "\\", with: "/").lowercased()
        #else
        return path
        #endif
    }

    /// Fixed keys and primitive values only. Paths and volume identifiers never enter this record.
    public var context: [String: Any] {
        var values: [String: Any] = [:]
        for (key, value) in [
            ("source_exists", sourceExists), ("source_readable", sourceReadable),
            ("target_exists_hint", targetExists), ("target_directory_hint", targetDirectory),
            ("target_writable_hint", targetWritable), ("parent_exists_hint", parentExists),
            ("parent_writable_hint", parentWritable), ("volume_local", volumeLocal),
            ("volume_removable", volumeRemovable), ("volume_read_only", volumeReadOnly),
            ("failure_path_exists_hint", failurePathExists), ("failure_parent_exists_hint", failureParentExists)
        ] {
            if let value { values[key] = value }
        }
        if let availableCapacityBytes, availableCapacityBytes >= 0 {
            values["filesystem_free_bytes"] = availableCapacityBytes
        }
        if let failurePathRole { values["failure_path_role"] = failurePathRole.rawValue }
        return values
    }
}
