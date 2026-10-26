#if os(Linux) || os(Windows)
import Foundation
import Dispatch
import CCairoRuntime

enum VideoExportSupport {
    static func throwIfCancelled(_ handler: (() -> Bool)?) throws {
        if handler?() == true { throw OverlayVideoError.cancelled }
    }
    static func installCompletedOutput(from completedURL: URL, to outputURL: URL,
        cancellationHandler: (() -> Bool)?, diagnosticsHandler: ((VideoExportDiagnosticEvent) -> Void)? = nil,
        replaceItem: (URL, URL) throws -> Void = { output, completed in
            let status = completed.withUnsafeFileSystemRepresentation { source in
                output.withUnsafeFileSystemRepresentation { target in
                    guard let source, let target else { return Int32(-1) }
                    return dls_replace_file(source, target)
                }
            }
            guard status == 0 else {
                throw NSError(domain: "run.libo.datalayer-studio.atomic-output", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not atomically install the export. The existing output was preserved."])
            }
        }
    ) throws {
        try throwIfCancelled(cancellationHandler)
        diagnosticsHandler?(.init(stage: .installOutput, phase: .update, operationStep: .outputCheckCompleted))
        try FileHandle(forReadingFrom: completedURL).close()
        diagnosticsHandler?(.init(stage: .installOutput, phase: .update, operationStep: .outputReplace))
        try replaceItem(outputURL, completedURL)
    }
}

enum PortableMedia {
    static func executable(_ name: String) throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        #if os(Windows)
        let path = environment.first { $0.key.lowercased() == "path" }?.value ?? ""
        let directories = path.split(separator: ";").map(String.init)
        let filename = name + ".exe"
        #else
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let filename = name
        #endif
        for directory in directories where !directory.isEmpty {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(filename)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw OverlayVideoError.invalidConfiguration("Install \(name) and add its executable directory to PATH.")
    }

    static func error(_ process: Process, log: URL) -> Error {
        let file = try? FileHandle(forReadingFrom: log)
        defer { try? file?.close() }
        let length = (try? file?.seekToEnd()) ?? 0
        try? file?.seek(toOffset: length > 65_536 ? length - 65_536 : 0)
        let detail = (try? file?.read(upToCount: 65_536)).flatMap { $0 }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return OverlayVideoError.writerFailed("FFmpeg process exited with status \(process.terminationStatus): \(detail)", underlying: NSError(domain: "run.libo.datalayer-studio.ffmpeg", code: Int(process.terminationStatus)))
    }

    static func probe(_ url: URL) throws -> Probe {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DataLayerStudio-Probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let errorFile = try FileHandle(forWritingTo: log)
        defer { try? errorFile.close() }
        let process = Process(), output = Pipe()
        process.executableURL = try executable("ffprobe")
        process.arguments = ["-v", "error", "-show_streams", "-show_format", "-of", "json", url.path]
        process.standardOutput = output; process.standardError = errorFile; process.standardInput = FileHandle.nullDevice
        try process.run()
        let watchdog = MediaProcessWatchdog(process: process, cancellation: nil)
        defer { watchdog.stop(); try? output.fileHandleForReading.close() }
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 4 * 1_024 * 1_024 {
                process.terminate(); process.waitUntilExit()
                throw OverlayVideoError.unreadableVideo("Video metadata exceeds the 4 MiB limit.")
            }
        }
        process.waitUntilExit()
        if let error = watchdog.error { throw error }
        guard process.terminationStatus == 0 else { throw error(process, log: log) }
        return try JSONDecoder().decode(Probe.self, from: data)
    }

    struct Probe: Decodable {
        var streams: [Stream]
        var format: Format?
        struct Format: Decodable { var duration: String?; var tags: [String: String]? }
        struct Stream: Decodable {
            var index: Int
            var codec_name: String?
            var codec_type: String?
            var nb_frames: String?
            var width: Int?
            var height: Int?
            var avg_frame_rate: String?
            var duration: String?
            var start_time: String?
            var bit_rate: String?
            var color_primaries: String?
            var color_transfer: String?
            var color_space: String?
            var color_range: String?
            var tags: [String: String]?
            var side_data_list: [SideData]?
            struct SideData: Decodable { var rotation: Int? }
        }
        var video: Stream? { streams.first { $0.codec_type == "video" } }
        var audio: [Stream] { streams.filter { $0.codec_type == "audio" } }
    }

    static func number(_ value: Double) -> String { String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value) }

    static func filterGraphOption(for executable: URL) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = executable; process.arguments = ["-hide_banner", "-h", "full"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        try process.run()
        let watchdog = MediaProcessWatchdog(process: process, cancellation: nil)
        defer { watchdog.stop(); try? output.fileHandleForReading.close() }
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 4 * 1_024 * 1_024 {
                process.terminate(); process.waitUntilExit()
                throw OverlayVideoError.invalidConfiguration("FFmpeg help exceeds the 4 MiB limit.")
            }
        }
        process.waitUntilExit()
        if let error = watchdog.error { throw error }
        guard process.terminationStatus == 0 else { throw OverlayVideoError.invalidConfiguration("Could not inspect FFmpeg filter graph support.") }
        // New FFmpeg removed the deprecated option in favor of the generic file-argument syntax.
        return String(decoding: data, as: UTF8.self).contains("-filter_complex_script") ? "-filter_complex_script" : "-/filter_complex"
    }
}

/// The watchdog also breaks a blocked pipe write if an encoder exits or stops reading input.
private final class MediaProcessWatchdog: @unchecked Sendable {
    private let lock = NSLock(), process: Process
    private let timer: DispatchSourceTimer
    private var lastActivity = ProcessInfo.processInfo.systemUptime
    private var storedError: Error?
    private var timeout: TimeInterval = 60
    var error: Error? { lock.lock(); defer { lock.unlock() }; return storedError }
    init(process: Process, cancellation: (() -> Bool)?) {
        self.process = process
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.setEventHandler { [weak self] in
            guard let self, process.isRunning else { return }
            let cancelled = cancellation?() == true
            self.lock.lock()
            let stalled = ProcessInfo.processInfo.systemUptime - self.lastActivity > self.timeout
            if self.storedError == nil, cancelled || stalled {
                self.storedError = cancelled ? OverlayVideoError.cancelled : VideoExportWaitError.stalled
            }
            let shouldStop = self.storedError != nil
            self.lock.unlock()
            if shouldStop { process.terminate() }
        }
        timer.schedule(deadline: .now(), repeating: .milliseconds(100)); timer.resume()
    }
    func activity(finishing: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        lastActivity = ProcessInfo.processInfo.systemUptime; timeout = finishing ? 120 : 60
    }
    func stop() { timer.cancel() }
    deinit { timer.cancel() }
}

extension VideoMetadata {
    public static func load(from url: URL) throws -> VideoMetadata {
        let start = Date()
        var details = importFileDiagnostics(url)
        details["import_phase"] = "duration"
        do { return try loadPortable(from: url) }
        catch {
            details["elapsed_seconds"] = max(0, Date().timeIntervalSince(start))
            let original = error as NSError
            var info = original.userInfo
            info["video_metadata"] = details
            throw NSError(domain: original.domain, code: original.code, userInfo: info)
        }
    }
    private static func loadPortable(from url: URL) throws -> VideoMetadata {
        let probe = try PortableMedia.probe(url)
        guard let stream = probe.video, let width = stream.width, let height = stream.height,
              width > 0, height > 0, let duration = Double(probe.format?.duration ?? stream.duration ?? ""), duration.isFinite, duration > 0 else {
            throw OverlayVideoError.unreadableVideo("No valid video track/duration found in \(url.lastPathComponent).")
        }
        let rate = (stream.avg_frame_rate ?? "").split(separator: "/").compactMap { Double($0) }
        let fps = rate.count == 2 && rate[1] > 0 ? rate[0] / rate[1] : 30
        let rotation = stream.side_data_list?.compactMap(\.rotation).first ?? Int(stream.tags?["rotate"] ?? "") ?? 0
        let rotated = abs(rotation % 180) == 90
        let formatter = ISO8601DateFormatter()
        func date(_ text: String?) -> Date? {
            guard let text else { return nil }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: text)
        }
        let tags = probe.format?.tags ?? [:]
        let resolvedDate = resolveCreationDate(containerCreationDate: date(tags["creation_time"]), explicitRecordingDate: date(tags["com.apple.quicktime.creationdate"]), writingApplication: tags["encoder"] ?? tags["software"])
        return VideoMetadata(size: CGSize(width: rotated ? height : width, height: rotated ? width : height), duration: duration,
                             framesPerSecond: fps.isFinite && fps > 0 ? fps : 30, bitRateBitsPerSecond: stream.bit_rate.flatMap(Double.init),
                             creationDate: resolvedDate.date, creationDateSource: resolvedDate.source,
                             colorInfo: VideoColorInfo(colorPrimaries: stream.color_primaries, transferFunction: stream.color_transfer, yCbCrMatrix: stream.color_space, isFullRange: stream.color_range.map { $0 == "pc" }))
    }
    public static func loadAsync(from url: URL) async throws -> VideoMetadata {
        try Task.checkCancellation(); let result = try load(from: url); try Task.checkCancellation(); return result
    }
}

public final class TransparentVideoWriter {
    private let outputURL: URL, series: TelemetrySeries, config: TransparentVideoWriterConfig
    public init(outputURL: URL, series: TelemetrySeries, config: TransparentVideoWriterConfig) {
        self.outputURL = outputURL; self.series = series; self.config = config
    }
    public func write() throws {
        let settings = TimelineVideoWriterConfig(width: config.width, height: config.height, framesPerSecond: config.framesPerSecond,
                                                timelineStart: config.startTime, duration: config.duration, averageBitRate: config.averageBitRate,
                                                codec: config.codec, activityTrim: config.activityTrim, progressHandler: config.progressHandler,
                                                cancellationHandler: config.cancellationHandler, diagnosticsHandler: config.diagnosticsHandler,
                                                temporaryDirectory: config.temporaryDirectory)
        let renderer = OverlayRenderer(series: series, config: OverlayRenderConfig(size: CGSize(width: config.width, height: config.height),
            timeSync: config.timeSync, activityOffsetMilliseconds: config.activityOffsetMilliseconds, fitClockOffsetMilliseconds: config.fitClockOffsetMilliseconds,
            layout: config.overlayLayout, distanceUnit: config.distanceUnit, timeZone: config.timeZone ?? .current, activityTrim: config.activityTrim))
        try PortableVideoExport.write(outputURL: outputURL, project: nil, config: settings) { time, buffer in
            try renderer.render(videoTime: time, into: buffer)
        }
    }
    public static func removeStaleTemporaryOutputs() {
        removeStaleTemporaryOutputs(in: FileManager.default.temporaryDirectory)
    }
    public static func removeStaleTemporaryOutputs(in directory: URL) {
        for entry in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? [] {
            let prefix = ".DataLayerStudio-Export-"
            guard entry.lastPathComponent.hasPrefix(prefix), UUID(uuidString: String(entry.lastPathComponent.dropFirst(prefix.count))) != nil,
                  let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: entry.appendingPathComponent("owner.json")),
                  let owner = try? JSONDecoder().decode(PortableExportOwner.self, from: data), owner.application == "DataLayer-CLI", owner.version == 1,
                  owner.createdAt.timeIntervalSinceNow < -60, dls_process_is_running(owner.pid) == 0,
                  let files = try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil),
                  files.allSatisfy({ ["owner.json", "output.mov", "filters.txt", "stderr.log"].contains($0.lastPathComponent) || $0.lastPathComponent.range(of: #"^lut-[0-9]+\.cube$"#, options: .regularExpression) != nil }) else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }
}

private struct PortableExportOwner: Codable {
    var application = "DataLayer-CLI"
    var version = 1
    var pid = ProcessInfo.processInfo.processIdentifier
    var createdAt = Date()
}

public final class TimelineVideoWriter {
    private let outputURL: URL, project: TimelineProject, telemetry: [String: TelemetrySeries], config: TimelineVideoWriterConfig
    public init(outputURL: URL, project: TimelineProject, telemetrySeriesByAssetID: [String: TelemetrySeries], config: TimelineVideoWriterConfig) {
        self.outputURL = outputURL; self.project = project; telemetry = telemetrySeriesByAssetID; self.config = config
    }
    public func write() throws -> VideoExportResult {
        let request = TimelineExportRequest(mode: config.codec.exportMode, codec: config.codec, width: config.width, height: config.height,
            framesPerSecond: config.framesPerSecond, timelineStart: config.timelineStart, duration: config.duration, bitRateKbps: config.averageBitRate / 1000)
        if let issue = TimelineExportService.firstPreflightIssue(for: request, project: project, availableTelemetryAssetIDs: Set(telemetry.keys)) {
            if case let .timeline(error) = issue { throw error }
            throw OverlayVideoError.invalidConfiguration("Invalid timeline export: \(issue)")
        }
        var renderers: [String: OverlayRenderer] = [:]
        for clip in project.enabledClips(kind: .overlay, timelineStart: config.timelineStart, duration: config.duration) {
            guard let asset = project.asset(id: clip.assetID), let series = telemetry[asset.id] else {
                throw OverlayVideoError.invalidConfiguration("Timeline overlay clip has no loaded activity.")
            }
            renderers[clip.id] = OverlayRenderer(series: series, config: OverlayRenderConfig(size: CGSize(width: config.width, height: config.height),
                timeSync: TelemetryTimeSync(videoSyncTime: 0, fitSyncTime: clip.sourceIn - clip.timelineStart),
                activityOffsetMilliseconds: asset.activityOffsetMilliseconds, fitClockOffsetMilliseconds: asset.fitClockOffsetMilliseconds,
                layout: clip.layout ?? .default, distanceUnit: clip.distanceUnit ?? project.distanceUnit,
                timeZone: project.displayTimeZone(for: asset), activityTrim: config.activityTrim))
        }
        let index = TimelineOverlayTimeIndex(project: project)
        let layer = CVPixelBuffer(width: config.width, height: config.height)
        try PortableVideoExport.write(outputURL: outputURL, project: project, config: config) { time, buffer in
            buffer.clear()
            for id in index.activeClipIDs(atTimelineTime: time) {
                guard let renderer = renderers[id] else { continue }
                try renderer.render(videoTime: time, into: layer); layer.composite(over: buffer)
            }
        }
        return .success
    }
}

enum PortableVideoExport {
    static func audioMixFilter(labels: [String], duration: Double) -> String {
        let samples = Int64((duration * 48_000).rounded(.up))
        // Missing EOF timestamps must not turn silence padding into an unbounded stream.
        return labels.map { "[\($0)]" }.joined() + "amix=inputs=\(labels.count):normalize=0,apad=whole_len=\(samples),atrim=end_sample=\(samples),asetpts=N/SR/TB[audio]"
    }

    static func write(outputURL: URL, project: TimelineProject?, config: TimelineVideoWriterConfig,
                      render: (TimeInterval, CVPixelBuffer) throws -> Void) throws {
        let request = TimelineExportRequest(mode: config.codec.exportMode, codec: config.codec, width: config.width, height: config.height,
            framesPerSecond: config.framesPerSecond, timelineStart: config.timelineStart, duration: config.duration, bitRateKbps: config.averageBitRate / 1000)
        guard TimelineExportService.validatedSettings(for: request) != nil else { throw OverlayVideoError.invalidConfiguration("Invalid video export settings.") }
        guard config.codec != .hevcAlpha else {
            throw OverlayVideoError.unsupportedEncoder("HEVC Alpha is not supported on Windows/Linux. Select ProRes 4444 to preserve transparency.")
        }
        if config.cancellationHandler?() == true { throw OverlayVideoError.cancelled }
        try PortableGraphics.check()
        let executable = try PortableMedia.executable("ffmpeg")
        let directory = outputURL.deletingLastPathComponent().appendingPathComponent(".DataLayerStudio-Export-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try JSONEncoder().encode(PortableExportOwner()).write(to: directory.appendingPathComponent("owner.json"), options: .atomic)
        let timing = TransparentVideoFrameTiming(framesPerSecond: config.framesPerSecond, duration: config.duration)
        guard !timing.frameCountWasClamped else { throw OverlayVideoError.invalidConfiguration("Export frame count is too large.") }
        let rate = "\(timing.frameDuration.timescale)/\(timing.frameDuration.value)"
        let frameClock = "settb=AVTB,setpts=N*\(timing.frameDuration.value)*1000000/\(timing.frameDuration.timescale)"
        let temp = directory.appendingPathComponent("output.mov"), log = directory.appendingPathComponent("stderr.log")
        var arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-threads", "2", "-filter_complex_threads", "1",
            "-f", "rawvideo", "-pixel_format", "bgra", "-video_size", "\(config.width)x\(config.height)", "-framerate", rate, "-i", "pipe:0"]
        var filters: [String] = [], audioLabels: [String] = [], videoLabel = "0:v"
        if config.codec.exportMode == .video {
            filters.append("color=c=black:s=\(config.width)x\(config.height):r=\(rate):d=\(PortableMedia.number(timing.outputDuration.seconds)),format=rgba,settb=1/120000000[base0]")
            videoLabel = "base0"
            let clips = try project?.validatedVideoClipsForExport(timelineStart: config.timelineStart, duration: config.duration) ?? []
            for (offset, clip) in clips.enumerated() {
                guard let asset = project?.asset(id: clip.assetID) else { throw OverlayVideoError.invalidConfiguration("Missing video asset.") }
                let probe = try PortableMedia.probe(asset.url)
                guard let stream = probe.video else { throw OverlayVideoError.unreadableVideo("No video stream in \(asset.displayName).") }
                arguments += ["-threads", "2", "-i", asset.url.path]
                let input = offset + 1, start = max(config.timelineStart, clip.timelineStart)
                let duration = min(config.timelineStart + config.duration, clip.timelineEnd) - start
                let source = clip.sourceIn + start - clip.timelineStart, destination = start - config.timelineStart
                let trackStart = Double(stream.start_time ?? "") ?? 0
                let sourceStart = trackStart + clip.sourceIn
                let phase = trackStart + source - destination + timing.frameDuration.seconds / 2
                let color = try colorFilters(clip: clip, asset: asset, directory: directory, index: offset)
                let matrix = stream.color_space == "bt2020nc" ? "bt2020" : stream.color_space == "smpte170m" || stream.color_space == "bt470bg" ? "bt601" : "bt709"
                let range = stream.color_range == "pc" ? "pc" : "tv"
                // Preserve source PTS and preroll: Apple's reader accepts the latest frame within half an output frame.
                filters.append("[\(input):v]trim=start=\(PortableMedia.number(trackStart)):end=\(PortableMedia.number(sourceStart + clip.duration)),settb=1/120000000,setpts=PTS-\(PortableMedia.number(phase))/TB\(color),scale=\(config.width):\(config.height):in_color_matrix=\(matrix):in_range=\(range):out_range=pc:force_original_aspect_ratio=decrease:flags=bicubic,pad=\(config.width):\(config.height):(ow-iw)/2:(oh-ih)/2:black,setsar=1,format=rgba[clip\(offset)]")
                let next = "base\(offset + 1)"
                filters.append("[\(videoLabel)][clip\(offset)]overlay=eof_action=repeat:repeatlast=1:format=rgb:x='if(gte(t,\(PortableMedia.number(destination)))*lt(t,\(PortableMedia.number(destination+duration))),0,NAN)'[\(next)]")
                videoLabel = next
                for stream in probe.audio {
                    let label = "audio\(input)_\(stream.index)"
                    let delay = Int64((destination * 48_000).rounded())
                    let audioStart = (Double(stream.start_time ?? "") ?? 0) + source
                    filters.append("[\(input):\(stream.index)]atrim=start=\(PortableMedia.number(audioStart)):duration=\(PortableMedia.number(duration)),asetpts=PTS-STARTPTS,aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,adelay=\(delay)S:all=1[\(label)]")
                    audioLabels.append(label)
                }
            }
            // Match Apple's Rec.709 ICC curve (502/256); zscale's 709 display curve uses a different gamma.
            // swscale expands RGB8/gray8 to 16 bits by shifting, so full white is 65280 at this boundary.
            let linear709 = rgbLUT("pow(min(val/65280,1),1.9609375)*65535")
            let linearSRGB = rgbLUT("if(lte(val/65280,0.04045),val/65280/12.92,pow((val/65280+0.055)/1.055,2.4))*65535")
            let mask = rgbLUT("min(val*65535/65280,65535)")
            let encoded709 = rgbLUT("pow(val/65535,1/1.9609375)*65535")
            filters.append("[\(videoLabel)]format=gbrp16le,\(linear709),format=gbrpf32le,\(frameClock)[linearVideo]")
            filters.append("[0:v]split[overlayRGB][overlayAlpha];[overlayRGB]format=gbrp16le,\(linearSRGB),format=gbrpf32le,\(frameClock)[linearOverlay];[overlayAlpha]alphaextract,setparams=range=full,format=gbrp16le,\(mask),format=gbrpf32le,\(frameClock)[alphaMask]")
            filters.append("[linearVideo][linearOverlay][alphaMask]maskedmerge,format=gbrp16le,\(encoded709),scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[video]")
            videoLabel = "video"
            if !audioLabels.isEmpty {
                filters.append(audioMixFilter(labels: audioLabels, duration: config.duration))
            }
        }
        if !filters.isEmpty {
            let script = directory.appendingPathComponent("filters.txt")
            try filters.joined(separator: ";\n").write(to: script, atomically: true, encoding: .utf8)
            arguments += [try PortableMedia.filterGraphOption(for: executable), script.path, "-map", "[\(videoLabel)]"]
        } else { arguments += ["-map", "0:v"] }
        if audioLabels.isEmpty { arguments += ["-an"] }
        else { arguments += ["-map", "[audio]", "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k"] }
        switch config.codec {
        case .h264: arguments += ["-c:v", "libx264", "-profile:v", "high", "-preset", "medium", "-b:v", "\(config.averageBitRate)", "-pix_fmt", "yuv420p"]
        case .hevc: arguments += ["-c:v", "libx265", "-preset", "medium", "-b:v", "\(config.averageBitRate)", "-pix_fmt", "yuv420p", "-tag:v", "hvc1", "-x265-params", "pools=2:frame-threads=1:log-level=error"]
        case .proRes4444: arguments += ["-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le", "-alpha_bits", "16"]
        case .hevcAlpha: preconditionFailure("Unsupported codec was rejected before creating output files")
        }
        // Limit video by its rational frame count; -t can round a fractional final frame down.
        // The audio graph is independently trimmed to the requested sample duration.
        arguments += ["-frames:v", "\(timing.frameCount)", "-video_track_timescale", "\(timing.mediaTimeScale)",
            "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-movflags", "+faststart", "-f", "mov", temp.path]
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let errorFile = try FileHandle(forWritingTo: log)
        defer { try? errorFile.close() }
        let process = Process(), input = Pipe()
        process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = directory
        process.standardInput = input; process.standardOutput = FileHandle.nullDevice; process.standardError = errorFile
        try process.run()
        let watchdog = MediaProcessWatchdog(process: process, cancellation: config.cancellationHandler)
        defer { watchdog.stop(); try? input.fileHandleForWriting.close() }
        do {
            let buffer = CVPixelBuffer(width: config.width, height: config.height)
            for frame in 0..<timing.frameCount {
                if config.cancellationHandler?() == true { throw OverlayVideoError.cancelled }
                if let error = watchdog.error { throw error }
                try render(config.timelineStart + timing.presentationTime(for: frame).seconds, buffer)
                try PortableGraphics.check()
                // Match the existing Apple ProRes export's premultiplied RGB/Alpha convention.
                let frameData = config.codec == .proRes4444
                    ? Data(bytes: buffer.pixels, count: buffer.bytesPerRow * buffer.height)
                    : buffer.straightAlphaData()
                try input.fileHandleForWriting.write(contentsOf: frameData)
                watchdog.activity(); config.progressHandler?(frame + 1, timing.frameCount)
            }
            try input.fileHandleForWriting.close(); watchdog.activity(finishing: true)
            process.waitUntilExit()
            if let error = watchdog.error { throw error }
            guard process.terminationStatus == 0 else { throw PortableMedia.error(process, log: log) }
        } catch {
            if process.isRunning { process.terminate() }; process.waitUntilExit()
            if let error = watchdog.error { throw error }
            if process.terminationStatus != 0, !(error is OverlayVideoError) { throw PortableMedia.error(process, log: log) }
            throw error
        }
        try VideoExportSupport.installCompletedOutput(from: temp, to: outputURL, cancellationHandler: config.cancellationHandler, diagnosticsHandler: config.diagnosticsHandler)
    }

    private static func rgbLUT(_ expression: String) -> String { "lutrgb=r='\(expression)':g='\(expression)':b='\(expression)'" }

    static func colorFilters(clip: TimelineClip, asset: MediaAsset, directory: URL, index: Int) throws -> String {
        let input = clip.colorSettings?.input == .automatic || clip.colorSettings == nil ? asset.colorInfo?.detectedInput ?? .rec709 : clip.colorSettings!.input
        if input == .log, clip.lut?.usage != .sourceConversion { throw CubeLUT.Failure.requiresSourceConversionLUT }
        var result = ""
        if input == .hlg || input == .pq {
            result += ",zscale=transfer=linear:npl=100,format=gbrpf32le,tonemap=tonemap=hable,zscale=primaries=bt709:transfer=bt709:matrix=bt709:range=limited"
        }
        if let lut = clip.lut, lut.intensity > 0 {
            let floats = lut.lut.cubeData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            var lines = ["LUT_3D_SIZE \(lut.lut.dimension)"]
            for offset in stride(from: 0, to: floats.count, by: 4) { lines.append("\(floats[offset]) \(floats[offset+1]) \(floats[offset+2])") }
            let filename = "lut-\(index).cube"
            try lines.joined(separator: "\n").write(to: directory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            // Use generated relative names: media/output paths never enter the filter expression.
            if lut.intensity < 1 {
                result += ",split[beforeLut\(index)][lutInput\(index)];[lutInput\(index)]lut3d=file=\(filename):interp=trilinear[lutOutput\(index)];[beforeLut\(index)][lutOutput\(index)]blend=all_mode=normal:all_opacity=\(PortableMedia.number(lut.intensity))"
            } else { result += ",lut3d=file=\(filename):interp=trilinear" }
        }
        return result
    }
}
#endif
