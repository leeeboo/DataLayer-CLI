#if canImport(AVFoundation)
import AVFoundation
import CoreGraphics
#endif
import Foundation

public struct VideoMetadata {
    public var size: CGSize
    public var duration: TimeInterval
    public var framesPerSecond: Double
    public var bitRateBitsPerSecond: Double?
    /// Recording start from the container's creation-date metadata; nil when the file carries none.
    public var creationDate: Date?
    public var creationDateSource: MediaWallClockSource?
    public var colorInfo: VideoColorInfo?

    public init(
        size: CGSize,
        duration: TimeInterval,
        framesPerSecond: Double,
        bitRateBitsPerSecond: Double? = nil,
        creationDate: Date? = nil,
        creationDateSource: MediaWallClockSource? = nil,
        colorInfo: VideoColorInfo? = nil
    ) {
        self.size = size
        self.duration = duration
        self.framesPerSecond = framesPerSecond
        self.bitRateBitsPerSecond = bitRateBitsPerSecond
        self.creationDate = creationDate
        self.creationDateSource = creationDateSource ?? (creationDate == nil ? nil : .containerMetadata)
        self.colorInfo = colorInfo
    }

    #if canImport(AVFoundation)
    public static func load(from url: URL) throws -> VideoMetadata {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = VideoMetadataResultBox()

        Task.detached {
            do {
                resultBox.set(.success(try await loadAsync(from: url)))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }

        semaphore.wait()
        guard let result = resultBox.result else {
            throw OverlayVideoError.unreadableVideo("Could not load video metadata from \(url.path).")
        }
        return try result.get()
    }

    public static func loadAsync(from url: URL) async throws -> VideoMetadata {
        let started = Date()
        var details = importFileDiagnostics(url)
        details["import_phase"] = "duration"
        do {
            let asset = AVURLAsset(url: url)
            let durationTime = try await asset.load(.duration)
            let duration = CMTimeGetSeconds(durationTime)
            if duration.isFinite { details["duration"] = duration }
            guard duration.isFinite, duration > 0 else {
                throw OverlayVideoError.unreadableVideo("Could not read a positive duration from \(url.path).")
            }

            details["import_phase"] = "video_tracks"
            let tracks = try await asset.loadTracks(withMediaType: .video)
            details["source_video_tracks"] = tracks.count
            guard let track = tracks.first else {
                throw OverlayVideoError.unreadableVideo("No video track found in \(url.path).")
            }

            details["import_phase"] = "natural_size"
            let naturalSize = try await track.load(.naturalSize)
            details["source_width"] = naturalSize.width
            details["source_height"] = naturalSize.height
            details["import_phase"] = "transform"
            let preferredTransform = try await track.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let size = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
            details["import_phase"] = "frame_rate"
            let nominalFrameRate = try await track.load(.nominalFrameRate)
            details["source_fps"] = nominalFrameRate
            let fps = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30
            details["import_phase"] = "optional_metadata"
            let formatDescriptions = try? await track.load(.formatDescriptions)
            let colorInfo = formatDescriptions?.first.flatMap(VideoColorInfo.read(from:))
            let estimatedDataRate = try? await track.load(.estimatedDataRate)
            let trackBitRate = estimatedDataRate.flatMap { rate -> Double? in
                let bitRate = Double(rate)
                return bitRate.isFinite && bitRate > 0 ? bitRate : nil
            }
            // Explicit recording metadata is stronger than the MP4 header date, which editors may
            // rewrite to the export time.
            let metadataFormats = (try? await asset.load(.availableMetadataFormats)) ?? []
            var metadataItems: [AVMetadataItem] = []
            for format in metadataFormats {
                if let items = try? await asset.loadMetadata(for: format) {
                    metadataItems.append(contentsOf: items)
                }
            }
            var explicitRecordingDate: Date?
            if let item = metadataItems.first(where: {
                $0.identifier?.rawValue == "mdta/com.apple.quicktime.creationdate"
            }) {
                explicitRecordingDate = try? await item.load(.dateValue)
            }
            var writingApplication: String?
            if let item = metadataItems.first(where: { $0.commonKey?.rawValue == "software" }) {
                writingApplication = try? await item.load(.stringValue)
            }
            var containerCreationDate: Date?
            if let creationDateItem = try? await asset.load(.creationDate) {
                containerCreationDate = try? await creationDateItem.load(.dateValue)
            }
            let resolvedDate = resolveCreationDate(
                containerCreationDate: containerCreationDate,
                explicitRecordingDate: explicitRecordingDate,
                writingApplication: writingApplication
            )
            return VideoMetadata(
                size: size,
                duration: duration,
                framesPerSecond: fps,
                bitRateBitsPerSecond: trackBitRate ?? fileBitRateBitsPerSecond(for: url, duration: duration),
                creationDate: resolvedDate.date,
                creationDateSource: resolvedDate.source,
                colorInfo: colorInfo
            )
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            details["elapsed_seconds"] = max(0, Date().timeIntervalSince(started))
            let original = error as NSError
            var info = original.userInfo
            // A code-owned scalar context, consumed by OverlayDiagnostics without a Core dependency.
            info["video_metadata"] = details
            throw NSError(domain: original.domain, code: original.code, userInfo: info)
        }
    }

    #endif

    static func importFileDiagnostics(_ url: URL) -> [String: Any] {
        guard url.isFileURL else { return [:] }
        let manager = FileManager.default
        #if canImport(AVFoundation)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        #else
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        #endif
        var details: [String: Any] = [
            "source_exists": manager.fileExists(atPath: url.path),
            "source_readable": manager.isReadableFile(atPath: url.path),
            "container_hint": "not_probed"
        ]
        if let size = values?.fileSize { details["source_file_bytes"] = size }
        if let regular = values?.isRegularFile { details["source_regular_file"] = regular }
        #if canImport(AVFoundation)
        if let cloud = values?.isUbiquitousItem { details["source_ubiquitous"] = cloud }
        if let status = values?.ubiquitousItemDownloadingStatus {
            details["source_cloud_available"] = status != .notDownloaded
        }
        let availableLocally = values?.isUbiquitousItem != true || values?.ubiquitousItemDownloadingStatus == .current || values?.ubiquitousItemDownloadingStatus == .downloaded
        #else
        let availableLocally = true
        #endif
        // Read only the 16-byte container signature of an available local file; never record bytes.
        if values?.isRegularFile == true,
           availableLocally,
           let file = try? FileHandle(forReadingFrom: url) {
            defer { try? file.close() }
            if let header = try? file.read(upToCount: 16) {
                if header.count >= 8, ["ftyp", "moov", "mdat", "wide", "free", "skip"].contains(String(decoding: header[4..<8], as: UTF8.self)) {
                    details["container_hint"] = "iso_bmff"
                } else if header.starts(with: [0x52, 0x49, 0x46, 0x46]) {
                    details["container_hint"] = "riff"
                } else if header.starts(with: [0x1a, 0x45, 0xdf, 0xa3]) {
                    details["container_hint"] = "ebml"
                } else {
                    details["container_hint"] = "unrecognized"
                }
            }
        }
        return details
    }

    static func resolveCreationDate(
        containerCreationDate: Date?,
        explicitRecordingDate: Date?,
        writingApplication: String?
    ) -> (date: Date?, source: MediaWallClockSource?) {
        if let explicitRecordingDate {
            return (explicitRecordingDate, .recordingMetadata)
        }
        // ponytail: only reject the verified editor signature; add more editors with sample-backed tests.
        if writingApplication?.localizedCaseInsensitiveContains("DaVinci Resolve") == true {
            return (nil, .untrustedExport)
        }
        return (containerCreationDate, containerCreationDate == nil ? nil : .containerMetadata)
    }

    private static func fileBitRateBitsPerSecond(for url: URL, duration: TimeInterval) -> Double? {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize > 0 else { return nil }
        let bitRate = Double(fileSize) * 8 / duration
        return bitRate.isFinite && bitRate > 0 ? bitRate : nil
    }
}

private final class VideoMetadataResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<VideoMetadata, Error>?

    var result: Result<VideoMetadata, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func set(_ result: Result<VideoMetadata, Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }
}

public enum OverlayVideoError: Error, CustomStringConvertible, LocalizedError, CustomNSError {
    case unreadableVideo(String, underlying: Error? = nil)
    case cannotCreatePixelBuffer
    case cannotCreateBitmapContext
    case cannotStartWriter(String, underlying: Error? = nil)
    case writerFailed(String, underlying: Error? = nil)
    case unsupportedEncoder(String)
    case invalidConfiguration(String)
    case cancelled

    public var description: String {
        switch self {
        case let .unreadableVideo(message, _):
            return message
        case .cannotCreatePixelBuffer:
            return "Could not create a 32-bit BGRA pixel buffer."
        case .cannotCreateBitmapContext:
            return "Could not create a bitmap context for overlay rendering."
        case let .cannotStartWriter(message, _):
            #if canImport(AVFoundation)
            return "Could not start AVAssetWriter: \(message)"
            #else
            return "Could not start the video encoder: \(message)"
            #endif
        case let .writerFailed(message, _):
            #if canImport(AVFoundation)
            return "AVAssetWriter failed: \(message)"
            #else
            return "Video encoder failed: \(message)"
            #endif
        case let .unsupportedEncoder(message):
            return message
        case let .invalidConfiguration(message):
            return message
        case .cancelled:
            return "Video export was cancelled."
        }
    }

    public var errorDescription: String? {
        description
    }

    // Stable codes survive Swift enum reordering and do not contain user input.
    public static var errorDomain: String { "run.libo.datalayer-studio.export" }
    public var errorCode: Int {
        switch self {
        case .unreadableVideo: return 1001
        case .cannotCreatePixelBuffer: return 1002
        case .cannotCreateBitmapContext: return 1003
        case .cannotStartWriter: return 1004
        case .writerFailed: return 1005
        case .unsupportedEncoder: return 1006
        case .invalidConfiguration: return 1007
        case .cancelled: return 1008
        }
    }
    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [NSLocalizedDescriptionKey: description]
        switch self {
        case let .unreadableVideo(_, underlying), let .cannotStartWriter(_, underlying), let .writerFailed(_, underlying):
            if let underlying { info[NSUnderlyingErrorKey] = underlying as NSError }
        default: break
        }
        return info
    }
}
