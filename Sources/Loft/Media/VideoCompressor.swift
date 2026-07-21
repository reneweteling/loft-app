import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum VideoCompressorError: LocalizedError {
    case unsupportedSource
    case noCompatiblePreset
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return "AVFoundation cannot read this file as a video."
        case .noCompatiblePreset:
            return "No H.265 preset is compatible with this video."
        case .exportFailed(let message):
            return "Compression failed: \(message)"
        }
    }
}

/// Re-encodes a video to H.265 at its original resolution.
///
/// Uses `AVAssetExportPresetHEVCHighestQuality`, which keeps the source
/// dimensions and frame rate and only swaps the codec. The deployment target is
/// macOS 14, so this goes through `exportAsynchronously` and polls `progress`
/// rather than the async `export(to:as:)` API added in macOS 15.
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
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard try await asset.load(.isExportable) else { throw VideoCompressorError.unsupportedSource }

        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        guard presets.contains(AVAssetExportPresetHEVCHighestQuality),
              let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw VideoCompressorError.noCompatiblePreset
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("loft-compress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("mp4")

        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let poller = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                progress(Double(session.progress))
            }
        }
        defer { poller.cancel() }

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    session.exportAsynchronously {
                        switch session.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        default:
                            continuation.resume(throwing: VideoCompressorError.exportFailed(
                                session.error?.localizedDescription ?? "unknown error"))
                        }
                    }
                }
            } onCancel: {
                session.cancelExport()
            }
        } catch {
            discard(output)
            throw error
        }

        progress(1.0)
        return output
    }

    /// Removes a compressed file and the temp directory it lives in.
    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func size(of url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}
