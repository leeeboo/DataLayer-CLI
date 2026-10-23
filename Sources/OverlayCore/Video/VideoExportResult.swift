import Foundation

public struct VideoExportWarning: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case videoSegmentSkipped
        case skippedSegmentAudioSilenced
    }

    public let kind: Kind
    public let clipID: String?
    public let sourceDisplayName: String
    public let timelineStart: TimeInterval
    public let duration: TimeInterval
    public let error: NSError?
    public let decodeAttemptCount: Int?

    public init(
        kind: Kind,
        clipID: String?,
        sourceDisplayName: String,
        timelineStart: TimeInterval,
        duration: TimeInterval,
        error: NSError? = nil,
        decodeAttemptCount: Int? = nil
    ) {
        self.kind = kind
        self.clipID = clipID
        self.sourceDisplayName = sourceDisplayName
        self.timelineStart = timelineStart
        self.duration = duration
        self.error = error
        self.decodeAttemptCount = decodeAttemptCount
    }
}

public struct VideoExportResult: Sendable, Equatable {
    public let warnings: [VideoExportWarning]

    public init(warnings: [VideoExportWarning] = []) {
        self.warnings = warnings
    }

    public static let success = VideoExportResult()
}
