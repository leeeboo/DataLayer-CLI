#if os(macOS)
import Darwin
import Foundation

/// App and CLI opt in at startup. Library callers can keep the in-process API.
public enum VideoExportWorker {
    public static var executableURL: URL?

    enum Job: Codable {
        case timeline(TimelineProject, [String: TelemetrySeries], TimelineVideoWriterConfig)
        case overlay(TelemetrySeries, TransparentVideoWriterConfig)
    }

    struct Request: Codable {
        let job: Job
        let directory: URL
        let bookmarks: [Data]
    }

    // Local IPC only. Error messages and warnings never enter the redacted diagnostic stream.
    final class Failure: Codable {
        let domain: String
        let code: Int
        let message: String
        let details: String?
        let underlying: Failure?

        init(_ error: Error, depth: Int = 0) {
            let error = error as NSError
            domain = error.domain; code = error.code; message = error.localizedDescription
            details = error.userInfo[NSDebugDescriptionErrorKey] as? String
            underlying = depth < 8 ? (error.userInfo[NSUnderlyingErrorKey] as? NSError).map {
                Failure($0, depth: depth + 1)
            } : nil
        }

        var error: NSError {
            var info: [String: Any] = [NSLocalizedDescriptionKey: message]
            if let details { info[NSDebugDescriptionErrorKey] = details }
            if let underlying { info[NSUnderlyingErrorKey] = underlying.error }
            return NSError(domain: domain, code: code, userInfo: info)
        }
    }

    struct Warning: Codable {
        let skippedVideo: Bool
        let clipID: String?
        let sourceDisplayName: String
        let timelineStart: Double
        let duration: Double
        let failure: Failure?
        let decodeAttemptCount: Int?

        init(_ value: VideoExportWarning) {
            skippedVideo = value.kind == .videoSegmentSkipped
            clipID = value.clipID; sourceDisplayName = value.sourceDisplayName
            timelineStart = value.timelineStart; duration = value.duration
            failure = value.error.map { Failure($0) }; decodeAttemptCount = value.decodeAttemptCount
        }

        var warning: VideoExportWarning {
            .init(kind: skippedVideo ? .videoSegmentSkipped : .skippedSegmentAudioSilenced,
                  clipID: clipID, sourceDisplayName: sourceDisplayName, timelineStart: timelineStart,
                  duration: duration, error: failure?.error, decodeAttemptCount: decodeAttemptCount)
        }
    }

    struct Message: Codable {
        var event: VideoExportDiagnosticEvent?
        var frame: Int?
        var total: Int?
        var warnings: [Warning]?
        var failure: Failure?
    }

    static func write(outputURL: URL, project: TimelineProject, telemetry: [String: TelemetrySeries],
                      config: TimelineVideoWriterConfig, executableURL: URL,
                      stallTimeout: TimeInterval = 120) throws -> VideoExportResult {
        let videoIDs = config.codec.exportMode == .video
            ? Set(try project.validatedVideoClipsForExport(timelineStart: config.timelineStart,
                                                          duration: config.duration).map(\.assetID)) : []
        let sourceURLs = project.assets.filter { videoIDs.contains($0.id) }.map(\.url)
        var attemptConfig = config
        while true {
            var failureEvent: VideoExportDiagnosticEvent?
            var lastOperation: VideoExportDiagnosticEvent?
            do {
                return try perform(job: .timeline(project, telemetry, attemptConfig), outputURL: outputURL,
                                   sourceURLs: sourceURLs, temporaryDirectory: config.temporaryDirectory,
                                   executableURL: executableURL, stallTimeout: stallTimeout,
                                   cancellation: config.cancellationHandler, progress: config.progressHandler,
                                   diagnostics: { event in
                                       if event.stage != .exportFailed && event.stage != .exportCompleted {
                                           lastOperation = event
                                           if event.phase == .failure { failureEvent = event }
                                       }
                                       config.diagnosticsHandler?(event)
                                   })
            } catch {
                try VideoExportSupport.throwIfCancelled(config.cancellationHandler)
                guard let next = fallback(config: attemptConfig, error: error, event: failureEvent ?? lastOperation) else { throw error }
                attemptConfig = next
            }
        }
    }

    static func fallback(config: TimelineVideoWriterConfig, error: Error,
                         event: VideoExportDiagnosticEvent?) -> TimelineVideoWriterConfig? {
        guard config.codec.exportMode == .video else { return nil }
        var cursor: NSError? = error as NSError
        while let current = cursor {
            if current.domain == NSPOSIXErrorDomain || current.domain == NSCocoaErrorDomain { return nil }
            if current.domain == OverlayVideoError.errorDomain, current.code == OverlayVideoError.cancelled.errorCode { return nil }
            if current.domain == VideoExportWaitError.errorDomain, current.code == VideoExportWaitError.cleanupPending.errorCode { return nil }
            cursor = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        var result = config
        switch event?.stage {
        case .readSource where !config.softwareDecoding:
            result.softwareDecoding = true
        case .prepareWriter, .awaitReady, .appendFrame, .finishInput, .finishWriter:
            guard !config.softwareEncoding else { return nil }
            result.softwareEncoding = true
        default:
            return nil
        }
        return result
    }

    static func writeOverlay(outputURL: URL, series: TelemetrySeries, config: TransparentVideoWriterConfig,
                             executableURL: URL) throws {
        _ = try perform(job: .overlay(series, config), outputURL: outputURL, sourceURLs: [], temporaryDirectory: config.temporaryDirectory,
                        executableURL: executableURL, cancellation: config.cancellationHandler,
                        progress: config.progressHandler, diagnostics: config.diagnosticsHandler)
    }

    private static func perform(job: Job, outputURL: URL, sourceURLs: [URL], temporaryDirectory: URL?, executableURL: URL,
                                stallTimeout: TimeInterval = 120, cancellation: (() -> Bool)?,
                                progress: ((Int, Int) -> Void)?,
                                diagnostics: ((VideoExportDiagnosticEvent) -> Void)?) throws -> VideoExportResult {
        try VideoExportCleanup.check()
        try VideoExportSupport.throwIfCancelled(cancellation)
        let access = ([outputURL] + sourceURLs).map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer { access.forEach { if $0.1 { $0.0.stopAccessingSecurityScopedResource() } } }
        // The App holds the selected root scope; transfer its scratch subdirectory grant to the child.
        let directory = (temporaryDirectory ?? FileManager.default.temporaryDirectory).appendingPathComponent(
            "DataLayerStudio-\(getpid())-worker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let process = Process()
        defer {
            if !process.isRunning { try? FileManager.default.removeItem(at: directory) }
        }
        // Ordinary bookmarks transfer the parent's live PowerBox grant to its inheriting child.
        var bookmarks: [Data] = try sourceURLs.compactMap { url in
            do { return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
            catch {
                let error = error as NSError
                // Let the existing timeline reader report a missing clip as a skipped-segment warning.
                if error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
                throw error
            }
        }
        if temporaryDirectory != nil {
            bookmarks.append(try directory.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        }
        let request = Request(job: job, directory: directory, bookmarks: bookmarks)
        let requestURL = directory.appendingPathComponent("request.plist")
        try PropertyListEncoder().encode(request).write(to: requestURL)
        let input = try FileHandle(forReadingFrom: requestURL)
        defer { try? input.close() }
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        process.executableURL = executableURL
        process.arguments = ["--video-worker", String(getpid())]
        process.standardInput = input
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let messages: [Warning]
        do {
            try String(process.processIdentifier).write(to: directory.appendingPathComponent("worker.pid"),
                                                        atomically: true, encoding: .utf8)
            try pipe.fileHandleForWriting.close()
            messages = try receive(process: process, pipe: pipe.fileHandleForReading,
                                   stallTimeout: stallTimeout, cancellation: cancellation,
                                   progress: progress, diagnostics: diagnostics)
        } catch {
            // Never retry or delete the staging directory until the old native stack is gone.
            if !stop(process) {
                let id = UUID()
                VideoExportCleanup.setPending(true, id: id)
                process.terminationHandler = { _ in
                    try? FileManager.default.removeItem(at: directory)
                    VideoExportCleanup.setPending(false, id: id)
                }
                // Process may have exited between the bounded wait and handler installation.
                if !process.isRunning { process.terminationHandler?(process) }
                throw VideoExportWaitError.cleanupPending
            }
            throw error
        }
        try VideoExportSupport.throwIfCancelled(cancellation)
        diagnostics?(.init(stage: .installOutput, phase: .begin))
        try VideoExportSupport.installCompletedOutput(from: directory.appendingPathComponent("completed.mov"),
                                                      to: outputURL, cancellationHandler: cancellation,
                                                      diagnosticsHandler: diagnostics)
        diagnostics?(.init(stage: .exportCompleted, phase: .end))
        return VideoExportResult(warnings: messages.map(\.warning))
    }

    static func receive(process: Process, pipe: FileHandle, stallTimeout: TimeInterval,
                        cancellation: (() -> Bool)?, progress: ((Int, Int) -> Void)?,
                        diagnostics: ((VideoExportDiagnosticEvent) -> Void)?) throws -> [Warning] {
        var pending = Data()
        var bytes = [UInt8](repeating: 0, count: 65_536)
        var lastActivity = ProcessInfo.processInfo.systemUptime
        var lastEvent: VideoExportDiagnosticEvent?
        var lastFrame = -1
        var result: [Warning]?
        var failure: Failure?
        var eof = false
        let fd = pipe.fileDescriptor
        while !eof || process.isRunning {
            try VideoExportSupport.throwIfCancelled(cancellation)
            if ProcessInfo.processInfo.systemUptime - lastActivity > stallTimeout {
                diagnostics?(.init(stage: lastEvent?.stage ?? .prepareTimeline, phase: .failure,
                                   errorDomain: VideoExportWaitError.errorDomain, errorCode: 1))
                throw VideoExportWaitError.stalled
            }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            if ready < 0 {
                if errno == EINTR { continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            if ready > 0 && !eof {
                let count = Darwin.read(fd, &bytes, bytes.count)
                if count < 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                if count == 0 { eof = true }
                if count > 0 { pending.append(contentsOf: bytes.prefix(count)) }
                guard pending.count <= 8 * 1_024 * 1_024 else { throw protocolFailure() }
                while let newline = pending.firstIndex(of: 10) {
                    let message = try JSONDecoder().decode(Message.self, from: pending.prefix(upTo: newline))
                    pending.removeSubrange(...newline)
                    if let event = message.event {
                        if event.stage != lastEvent?.stage || event.phase != lastEvent?.phase
                            || event.frameIndex != lastEvent?.frameIndex || event.preparationStep != lastEvent?.preparationStep
                            || event.operationStep != lastEvent?.operationStep || event.sourceIndex != lastEvent?.sourceIndex
                            || event.exportProgress != lastEvent?.exportProgress {
                            lastActivity = ProcessInfo.processInfo.systemUptime
                        }
                        lastEvent = event
                        // The helper installs only its private artifact. Completion belongs to the parent.
                        if event.stage != .installOutput && event.stage != .exportCompleted { diagnostics?(event) }
                        if event.stage == .readSource, event.phase == .failure, event.decodeTimeoutSeconds != nil {
                            throw OverlayVideoError.unreadableVideo("Source video reading timed out.",
                                underlying: NSError(domain: "run.libo.datalayer-studio.decoder", code: 1))
                        }
                    }
                    if let frame = message.frame, let total = message.total {
                        if frame != lastFrame { lastActivity = ProcessInfo.processInfo.systemUptime; lastFrame = frame }
                        progress?(frame, total)
                    }
                    if let warnings = message.warnings { result = warnings }
                    if let error = message.failure { failure = error }
                }
            }
            if eof && process.isRunning { Thread.sleep(forTimeInterval: 0.01) }
        }
        process.waitUntilExit()
        if let failure { throw failure.error }
        guard process.terminationStatus == 0, pending.isEmpty, let result else {
            diagnostics?(.init(stage: lastEvent?.stage ?? .prepareTimeline, phase: .failure,
                               errorDomain: "run.libo.datalayer-studio.export.worker",
                               errorCode: Int(process.terminationStatus)))
            throw protocolFailure()
        }
        return result
    }

    @discardableResult
    static func stop(_ process: Process) -> Bool {
        guard process.isRunning else { return true }
        process.terminate()
        let grace = ProcessInfo.processInfo.systemUptime + 0.2
        while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
        return !process.isRunning
    }

    static func protocolFailure() -> NSError {
        NSError(domain: "run.libo.datalayer-studio.export.worker", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The video export worker ended without a complete result."])
    }

    /// One request per process; _exit also reclaims any decoder thread that ignored cancellation.
    public static func run() -> Never {
        let parent = CommandLine.arguments.last.flatMap(Int32.init) ?? getppid()
        DispatchQueue.global(qos: .utility).async {
            while getppid() == parent { Thread.sleep(forTimeInterval: 0.2) }
            _exit(1)
        }
        let lock = NSLock()
        func send(_ message: Message) {
            lock.lock(); defer { lock.unlock() }
            do {
                var data = try JSONEncoder().encode(message)
                data.append(10)
                try FileHandle.standardOutput.write(contentsOf: data)
            } catch { _exit(1) }
        }
        do {
            let data = try FileHandle.standardInput.read(upToCount: 64 * 1_024 * 1_024 + 1) ?? Data()
            guard data.count <= 64 * 1_024 * 1_024 else { throw protocolFailure() }
            let request = try PropertyListDecoder().decode(Request.self, from: data)
            var scopes: [(URL, Bool)] = []
            for bookmark in request.bookmarks {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
                scopes.append((url, url.startAccessingSecurityScopedResource()))
            }
            defer { scopes.forEach { if $0.1 { $0.0.stopAccessingSecurityScopedResource() } } }
            VideoExportSupport.temporaryDirectory = request.directory
            let output = request.directory.appendingPathComponent("completed.mov")
            let progress: (Int, Int) -> Void = { send(.init(frame: $0, total: $1)) }
            let diagnostics: (VideoExportDiagnosticEvent) -> Void = { send(.init(event: $0)) }
            let result: VideoExportResult
            switch request.job {
            case .timeline(let project, let telemetry, var config):
                config.progressHandler = progress; config.diagnosticsHandler = diagnostics
                result = try TimelineVideoWriter(outputURL: output, project: project,
                                                telemetrySeriesByAssetID: telemetry, config: config).writeUnmonitored()
            case .overlay(let series, var config):
                config.progressHandler = progress; config.diagnosticsHandler = diagnostics
                try TransparentVideoWriter(outputURL: output, series: series, config: config).writeUnmonitored()
                result = .success
            }
            send(.init(warnings: result.warnings.map(Warning.init)))
            _exit(0)
        } catch {
            send(.init(failure: Failure(error)))
            _exit(1)
        }
    }
}
#endif
