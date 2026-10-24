#if canImport(AVFoundation)
import AudioToolbox
import AVFoundation
import CoreMedia
import CoreVideo
@testable import OverlayCore
import XCTest

final class TimelineAudioTrackReuseTests: XCTestCase {
    func testTimelineCompositionKeepsParallelSourceAudioTracksSeparate() async throws {
        let sourceURL = temporaryMovieURL("timeline-parallel-audio-source")
        defer { Self.removeTemporaryFile(sourceURL) }
        try makeTinySourceVideo(at: sourceURL, audioTrackCount: 2)

        let asset = MediaAsset(
            id: "video",
            kind: .video,
            url: sourceURL,
            displayName: sourceURL.lastPathComponent,
            duration: 1,
            width: 64,
            height: 64,
            framesPerSecond: 2
        )
        let clip = TimelineClip(id: "clip", assetID: asset.id, timelineStart: 0, duration: 1)
        let project = TimelineProject(
            outputWidth: 64,
            outputHeight: 64,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            assets: [asset],
            tracks: [TimelineTrack(id: "video", kind: .video, name: "V1", clips: [clip])]
        )

        let built = try TimelineVideoCompositionBuilder.make(
            project: project,
            videoClips: [clip],
            requiredEnd: 1
        )
        XCTAssertEqual(built.composition.tracks(withMediaType: .audio).count, 2)
        let outputURL = temporaryMovieURL("timeline-parallel-audio-output")
        defer { Self.removeTemporaryFile(outputURL) }
        try TimelineVideoWriter(outputURL: outputURL, project: project, telemetrySeriesByAssetID: [:],
            config: TimelineVideoWriterConfig(width: 64, height: 64, framesPerSecond: 2,
                                              duration: 1, averageBitRate: 200_000, codec: .h264)).write()
        let exportedTracks = try await AVURLAsset(url: outputURL).loadTracks(withMediaType: .audio)
        XCTAssertEqual(exportedTracks.count, 2, "Single-pass export must preserve parallel source audio tracks.")
    }

    func testTimelineWriterReusesCompatibleAudioTrackAcrossSparseClips() async throws {
        let sourceCount = 23
        let sourceURL = temporaryMovieURL("timeline-audio-reuse-source")
        let sourceURLs = (0..<sourceCount).map { index in
            temporaryMovieURL("timeline-audio-reuse-\(index)")
        }
        let outputURL = temporaryMovieURL("timeline-audio-reuse-output")
        defer {
            [sourceURL, outputURL].forEach(Self.removeTemporaryFile)
            sourceURLs.forEach(Self.removeTemporaryFile)
        }

        try makeTinySourceVideo(at: sourceURL)
        for destinationURL in sourceURLs {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }

        let gapStart = 12.0
        let gapDuration = 0.5
        let assets = sourceURLs.enumerated().map { index, url in
            MediaAsset(
                id: "video-\(index)",
                kind: .video,
                url: url,
                displayName: url.lastPathComponent,
                duration: 1,
                width: 64,
                height: 64,
                framesPerSecond: 2
            )
        }
        let clips = (0..<sourceCount).map { index in
            TimelineClip(
                id: "clip-\(index)",
                assetID: "video-\(index)",
                timelineStart: Double(index) + (index >= Int(gapStart) ? gapDuration : 0),
                duration: 1
            )
        }
        let duration = Double(sourceCount) + gapDuration
        let activity = MediaAsset(
            id: "activity",
            kind: .activity,
            url: URL(fileURLWithPath: "/tmp/timeline-audio-reuse.fit"),
            displayName: "timeline-audio-reuse.fit",
            duration: duration
        )
        let project = TimelineProject(
            outputWidth: 64,
            outputHeight: 64,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            assets: assets + [activity],
            tracks: [
                TimelineTrack(id: "video", kind: .video, name: "V1", clips: clips),
                TimelineTrack(
                    id: "overlay",
                    kind: .overlay,
                    name: "O1",
                    clips: [
                        TimelineClip(
                            id: "empty-overlay",
                            assetID: activity.id,
                            timelineStart: 0,
                            duration: duration,
                            layout: OverlayLayout(elements: [])
                        )
                    ]
                )
            ]
        )

        let built = try TimelineVideoCompositionBuilder.make(
            project: project,
            videoClips: clips,
            requiredEnd: duration
        )
        XCTAssertEqual(
            built.composition.tracks(withMediaType: .audio).count,
            1,
            "Compatible non-overlapping clips should share one composition audio track."
        )

        let writer = TimelineVideoWriter(
            outputURL: outputURL,
            project: project,
            telemetrySeriesByAssetID: [
                activity.id: TelemetrySeries(samples: [
                    TelemetrySample(elapsed: 0, distanceMeters: 0),
                    TelemetrySample(elapsed: duration, distanceMeters: duration)
                ])
            ],
            config: TimelineVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: duration,
                averageBitRate: 200_000,
                codec: .h264
            )
        )
        do {
            try writer.write()
        } catch let error as OverlayVideoError {
            switch error {
            case .unsupportedEncoder, .cannotStartWriter:
                throw XCTSkip("Timeline audio-reuse test encoder is unavailable on this Mac: \(error.description)")
            default:
                throw error
            }
        }

        let openingAudio = try await audioMeanAbsoluteAmplitude(from: outputURL, at: 0.25)
        let middleAudio = try await audioMeanAbsoluteAmplitude(from: outputURL, at: 11.25)
        let endingAudio = try await audioMeanAbsoluteAmplitude(from: outputURL, at: 22.75)
        let gapAudio = try await audioMeanAbsoluteAmplitude(from: outputURL, at: gapStart + 0.25)
        XCTAssertGreaterThan(openingAudio, 1_000)
        XCTAssertGreaterThan(middleAudio, 1_000)
        XCTAssertGreaterThan(endingAudio, 1_000)
        XCTAssertLessThan(gapAudio, 100)
    }

    private func temporaryMovieURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
            .appendingPathExtension("mov")
    }

    private static func removeTemporaryFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func makeTinySourceVideo(at url: URL, audioTrackCount: Int = 1) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        let audioInputs = (0..<audioTrackCount).map { _ in
            AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
        }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(videoInput), audioInputs.allSatisfy(writer.canAdd) else {
            throw OverlayVideoError.unsupportedEncoder("Could not create compatible timeline audio fixture.")
        }
        writer.add(videoInput)
        audioInputs.forEach(writer.add)
        guard writer.startWriting() else {
            throw OverlayVideoError.cannotStartWriter(writer.error?.localizedDescription ?? "Could not start timeline audio fixture.")
        }
        writer.startSession(atSourceTime: .zero)
        for frameIndex in 0..<2 {
            while !videoInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard adaptor.append(try makePixelBuffer(), withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: 2)) else {
                throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Could not append timeline audio fixture video.")
            }
        }
        videoInput.markAsFinished()
        for (index, audioInput) in audioInputs.enumerated() {
            while !audioInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard audioInput.append(try makeAudioSampleBuffer(fillByte: UInt8(64 + index))) else {
                throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Could not append timeline audio fixture audio.")
            }
            audioInput.markAsFinished()
        }
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard writer.status == .completed else {
            throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Timeline audio fixture failed.")
        }
    }

    private func makePixelBuffer() throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        return pixelBuffer
    }

    private func makeAudioSampleBuffer(fillByte: UInt8 = 64) throws -> CMSampleBuffer {
        let sampleCount = 44_100
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else {
            throw OverlayVideoError.writerFailed("Could not create timeline audio fixture format.")
        }
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: sampleCount * 2,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: sampleCount * 2,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer,
        CMBlockBufferFillDataBytes(
            with: Int8(bitPattern: fillByte),
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: sampleCount * 2
        ) == noErr else {
            throw OverlayVideoError.writerFailed("Could not create timeline audio fixture data.")
        }
        var sampleBuffer: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: sampleCount,
            presentationTimeStamp: .zero,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else {
            throw OverlayVideoError.writerFailed("Could not create timeline audio fixture sample.")
        }
        return sampleBuffer
    }

    private func audioMeanAbsoluteAmplitude(from url: URL, at seconds: TimeInterval) async throws -> Double {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return 0 }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: seconds, preferredTimescale: 44_100),
            duration: CMTime(seconds: 0.25, preferredTimescale: 44_100)
        )
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var total = 0.0
        var count = 0
        while let sampleBuffer = output.copyNextSampleBuffer(),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            let byteCount = CMBlockBufferGetDataLength(blockBuffer)
            var bytes = [UInt8](repeating: 0, count: byteCount)
            let status = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: byteCount, destination: $0.baseAddress!)
            }
            XCTAssertEqual(status, noErr)
            for index in stride(from: 0, to: byteCount - 1, by: 2) {
                let sample = Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
                total += abs(Double(sample))
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }
}

#endif
