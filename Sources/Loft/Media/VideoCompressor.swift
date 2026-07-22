import AVFoundation
import Foundation
import UniformTypeIdentifiers
import VideoToolbox

enum VideoCompressorError: LocalizedError {
    case unsupportedSource
    case noVideoTrack
    case readerFailed(String)
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return "AVFoundation cannot read this file as a video."
        case .noVideoTrack:
            return "This file has no video track to compress."
        case .readerFailed(let message):
            return "Compression failed while reading: \(message)"
        case .writerFailed(let message):
            return "Compression failed while writing: \(message)"
        }
    }
}

/// Re-encodes a video to H.265 at its original resolution and frame rate.
///
/// Uses `AVAssetReader` + `AVAssetWriter` rather than `AVAssetExportSession`.
/// The export presets only offer fixed *quality* (e.g. `HEVCHighestQuality`),
/// which re-encodes an already-efficient source at a *higher* bitrate and
/// inflates the file. A writer lets us set an explicit target bitrate, so the
/// result is genuinely smaller. On Apple Silicon the HEVC encode runs on the
/// media engine via VideoToolbox, the same hardware path HandBrake's "Apple
/// VideoToolbox" presets use.
enum VideoCompressor {
    /// Extension-based check, deliberately cheap: this runs on the main actor
    /// while a drop is being handled, where loading an AVAsset would stall.
    static func isVideo(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    /// Returns the compressed file in its own temp directory. The caller owns
    /// that directory and should pass it to ``discard(_:)`` once uploaded.
    static func compress(source: URL,
                         bitsPerPixel: Double = VideoCompressionQuality.balanced.bitsPerPixel,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoCompressorError.noVideoTrack
        }

        let (naturalSize, transform, nominalFrameRate, estimatedDataRate) = try await (
            videoTrack.load(.naturalSize),
            videoTrack.load(.preferredTransform),
            videoTrack.load(.nominalFrameRate),
            videoTrack.load(.estimatedDataRate)
        )
        let duration = try await asset.load(.duration)
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        let width = abs(Int(naturalSize.width.rounded()))
        let height = abs(Int(naturalSize.height.rounded()))
        guard width > 0, height > 0 else { throw VideoCompressorError.unsupportedSource }

        let fps = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30
        var targetBitrate = Int(Double(width * height) * fps * bitsPerPixel)
        // Never aim above the source: for an already-lean video there is nothing
        // to gain, and the caller's "not smaller" guard will keep the original.
        if estimatedDataRate > 0 {
            targetBitrate = min(targetBitrate, Int(Double(estimatedDataRate) * 0.85))
        }
        targetBitrate = max(targetBitrate, 200_000)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("loft-compress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("mp4")

        do {
            try await transcode(asset: asset,
                                videoTrack: videoTrack,
                                audioTrack: audioTrack,
                                output: output,
                                width: width,
                                height: height,
                                transform: transform,
                                fps: fps,
                                bitrate: targetBitrate,
                                totalSeconds: duration.seconds,
                                progress: progress)
        } catch {
            discard(output)
            throw error
        }

        progress(1.0)
        return output
    }

    private static func transcode(asset: AVURLAsset,
                                  videoTrack: AVAssetTrack,
                                  audioTrack: AVAssetTrack?,
                                  output: URL,
                                  width: Int,
                                  height: Int,
                                  transform: CGAffineTransform,
                                  fps: Double,
                                  bitrate: Int,
                                  totalSeconds: Double,
                                  progress: @escaping @Sendable (Double) -> Void) async throws {
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw VideoCompressorError.readerFailed("cannot read video") }
        reader.add(videoOutput)

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0
        ]
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compression
            ])
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else { throw VideoCompressorError.writerFailed("cannot write HEVC") }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack {
            let out = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            out.alwaysCopiesSampleData = false
            if reader.canAdd(out) {
                reader.add(out)
                let asbd = try? await audioTrack.load(.formatDescriptions).first
                    .map { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
                let channels = Int(asbd??.mChannelsPerFrame ?? 2)
                let sampleRate = (asbd??.mSampleRate).map { $0 > 0 ? $0 : 44_100 } ?? 44_100
                let input = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVNumberOfChannelsKey: max(1, channels),
                        AVSampleRateKey: sampleRate,
                        AVEncoderBitRateKey: 128_000
                    ])
                input.expectsMediaDataInRealTime = false
                if writer.canAdd(input) {
                    writer.add(input)
                    audioOutput = out
                    audioInput = input
                }
            }
        }

        guard reader.startReading() else {
            throw VideoCompressorError.readerFailed(reader.error?.localizedDescription ?? "startReading")
        }
        guard writer.startWriting() else {
            throw VideoCompressorError.writerFailed(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)

        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await pump(input: videoInput,
                                   output: videoOutput,
                                   label: "video",
                                   totalSeconds: totalSeconds,
                                   progress: progress)
                }
                if let audioInput, let audioOutput {
                    group.addTask {
                        try await pump(input: audioInput,
                                       output: audioOutput,
                                       label: "audio",
                                       totalSeconds: 0,
                                       progress: nil)
                    }
                }
                try await group.waitForAll()
            }

            if reader.status == .failed {
                throw VideoCompressorError.readerFailed(reader.error?.localizedDescription ?? "read failed")
            }
            await writer.finishWriting()
            if writer.status == .failed {
                throw VideoCompressorError.writerFailed(writer.error?.localizedDescription ?? "write failed")
            }
        } onCancel: {
            reader.cancelReading()
            writer.cancelWriting()
        }
    }

    /// Drives one writer input from one reader output. `requestMediaDataWhenReady`
    /// calls back on a serial queue whenever the encoder can take more samples;
    /// the continuation resumes once this track is drained or cancelled.
    private static func pump(input: AVAssetWriterInput,
                             output: AVAssetReaderTrackOutput,
                             label: String,
                             totalSeconds: Double,
                             progress: (@Sendable (Double) -> Void)?) async throws {
        let queue = DispatchQueue(label: "com.weteling.loft.compress.\(label)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if Task.isCancelled {
                        input.markAsFinished()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    if !input.append(sample) {
                        input.markAsFinished()
                        continuation.resume(throwing: VideoCompressorError.writerFailed("append rejected (\(label))"))
                        return
                    }
                    if let progress, totalSeconds > 0 {
                        let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        if t.isFinite { progress(min(0.99, max(0, t / totalSeconds))) }
                    }
                }
            }
        }
    }

    /// Removes a compressed file and the temp directory it lives in.
    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func size(of url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}
