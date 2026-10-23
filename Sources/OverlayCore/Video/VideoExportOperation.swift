import Foundation

public enum VideoExportWaitError: Error, LocalizedError, CustomNSError {
    case stalled
    case cleanupPending

    public static var errorDomain: String { "run.libo.datalayer-studio.export.wait" }
    public var errorCode: Int { self == .stalled ? 1 : 2 }
    public var errorDescription: String? {
        self == .stalled
            ? "Video encoding stopped making progress. The export has been stopped."
            : "The previous video export is still stopping. Try again after it finishes, or restart the app."
    }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription ?? ""] }
}

enum VideoExportCleanup {
    static let lock = NSLock()
    static var pending = Set<UUID>()

    static func check() throws {
        lock.lock()
        defer { lock.unlock() }
        if !pending.isEmpty { throw VideoExportWaitError.cleanupPending }
    }

    static func setPending(_ pending: Bool, id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if pending { self.pending.insert(id) } else { self.pending.remove(id) }
    }
}

/// The worker retains its writer, buffers and file scopes until AVFoundation actually returns.
final class VideoExportOperation: @unchecked Sendable {
    private let lock = NSLock()
    private let id = UUID()
    private let cancellationHandler: (() -> Bool)?
    private var progressHandler: ((Int, Int) -> Void)?
    private var diagnosticsHandler: ((VideoExportDiagnosticEvent) -> Void)?
    private var stopped = false
    private var completed = false
    private var installingOutput = false
    private var lastActivity = ProcessInfo.processInfo.systemUptime
    private var lastFrame = -1
    private var latestEvent: VideoExportDiagnosticEvent?

    init(cancellationHandler: (() -> Bool)?, progressHandler: ((Int, Int) -> Void)?,
         diagnosticsHandler: ((VideoExportDiagnosticEvent) -> Void)?) {
        self.cancellationHandler = cancellationHandler
        self.progressHandler = progressHandler
        self.diagnosticsHandler = diagnosticsHandler
    }

    var isCancelled: Bool {
        lock.lock()
        let stopped = self.stopped
        lock.unlock()
        return stopped || cancellationHandler?() == true
    }

    func recordProgress(_ frame: Int, _ total: Int) {
        lock.lock()
        if frame != lastFrame { lastActivity = ProcessInfo.processInfo.systemUptime; lastFrame = frame }
        let handler = progressHandler
        lock.unlock()
        handler?(frame, total)
    }

    func recordDiagnostic(_ event: VideoExportDiagnosticEvent) {
        lock.lock()
        if event.stage != latestEvent?.stage || event.phase != latestEvent?.phase
            || event.frameIndex != latestEvent?.frameIndex {
            lastActivity = ProcessInfo.processInfo.systemUptime
        }
        latestEvent = event
        // Once installation starts, report its real result instead of abandoning an atomic replacement.
        if event.stage == .installOutput { installingOutput = true }
        let handler = diagnosticsHandler
        lock.unlock()
        handler?(event)
    }

    func stopIfNeeded(renderTimeout: TimeInterval, finishTimeout: TimeInterval) -> Error? {
        let cancelled = cancellationHandler?() == true
        lock.lock()
        defer { lock.unlock() }
        guard !completed, !installingOutput else { return nil }
        let idle = ProcessInfo.processInfo.systemUptime - lastActivity
        let stalled = (latestEvent?.stage == .awaitReady && idle >= renderTimeout)
            || (latestEvent?.stage == .finishWriter && idle >= finishTimeout)
        guard cancelled || stalled else { return nil }
        stopped = true
        progressHandler = nil
        diagnosticsHandler = nil
        VideoExportCleanup.setPending(true, id: id)
        return cancelled ? OverlayVideoError.cancelled : VideoExportWaitError.stalled
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        completed = true
        VideoExportCleanup.setPending(false, id: id)
    }
}

private final class VideoExportOperationResult<Value>: @unchecked Sendable {
    var result: Result<Value, Error>?
}

extension VideoExportSupport {
    static func performWriting<Value>(
        cancellationHandler: (() -> Bool)?,
        progressHandler: ((Int, Int) -> Void)? = nil,
        diagnosticsHandler: ((VideoExportDiagnosticEvent) -> Void)? = nil,
        securityScopedURLs: [URL] = [],
        renderTimeout: TimeInterval = 60,
        finishTimeout: TimeInterval = 120,
        operation: @escaping (VideoExportOperation) throws -> Value
    ) throws -> Value {
        try throwIfCancelled(cancellationHandler)
        try VideoExportCleanup.check()
        let control = VideoExportOperation(cancellationHandler: cancellationHandler,
                                           progressHandler: progressHandler, diagnosticsHandler: diagnosticsHandler)
        let result = VideoExportOperationResult<Value>()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let access = securityScopedURLs.map { ($0, $0.startAccessingSecurityScopedResource()) }
            result.result = Result {
                try throwIfCancelled({ control.isCancelled })
                return try operation(control)
            }
            access.forEach { url, started in if started { url.stopAccessingSecurityScopedResource() } }
            control.finish()
            finished.signal()
        }
        while finished.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if let error = control.stopIfNeeded(renderTimeout: renderTimeout, finishTimeout: finishTimeout) {
                // Give ordinary cancellation a short cleanup window without waiting on a stuck encoder.
                _ = finished.wait(timeout: .now() + .milliseconds(200))
                throw error
            }
        }
        return try result.result!.get()
    }
}
