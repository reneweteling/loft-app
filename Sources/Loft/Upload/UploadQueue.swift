import Foundation
import SwiftUI

/// A dropped video that crossed the size threshold and is waiting for the user
/// to answer the compress prompt in the popover.
struct PendingCompression: Identifiable {
    let id = UUID()
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    let pane: Pane
}

@MainActor
final class UploadQueue: ObservableObject {
    static let shared = UploadQueue()

    @Published var items: [UploadItem] = []
    @Published var pendingCompressions: [PendingCompression] = []
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    var isActive: Bool {
        items.contains { !$0.state.isTerminal }
    }

    func enqueue(fileURLs: [URL], pane: Pane) {
        let config = AppConfig.shared
        for url in fileURLs {
            let size = VideoCompressor.size(of: url)
            let route = CompressionRoute.decide(isVideo: VideoCompressor.isVideo(url),
                                                fileSize: size,
                                                thresholdMB: config.videoCompressionThresholdMB,
                                                policy: config.videoCompressionPolicy)
            switch route {
            case .ask:
                pendingCompressions.append(PendingCompression(fileURL: url,
                                                              fileName: url.lastPathComponent,
                                                              fileSize: size,
                                                              pane: pane))
            case .compress:
                start(url: url, pane: pane, compress: true)
            case .asIs:
                start(url: url, pane: pane, compress: false)
            }
        }
    }

    /// Answers one prompt. `remember` writes the choice to settings and applies
    /// it to every other prompt still on screen, so a batch drop is one click.
    func resolvePendingCompression(id: UUID, compress: Bool, remember: Bool) {
        guard let index = pendingCompressions.firstIndex(where: { $0.id == id }) else { return }
        let pending = pendingCompressions.remove(at: index)
        var rest: [PendingCompression] = []
        if remember {
            AppConfig.shared.videoCompressionPolicy = compress ? .always : .never
            rest = pendingCompressions
            pendingCompressions.removeAll()
        }
        start(url: pending.fileURL, pane: pending.pane, compress: compress)
        for other in rest {
            start(url: other.fileURL, pane: other.pane, compress: compress)
        }
    }

    func dismissPendingCompression(id: UUID) {
        pendingCompressions.removeAll { $0.id == id }
    }

    private func start(url: URL, pane: Pane, compress: Bool) {
        let item = UploadItem(fileURL: url, paneId: pane.id)
        items.append(item)
        let enqueueProps: [String: Any] = [
            "pane": pane.name,
            "ttl": pane.ttl.tagValue,
            "visibility": pane.visibility.rawValue,
            "sizeBytes": item.fileSize,
            "compress": compress
        ]
        Telemetry.event("upload.enqueued", data: enqueueProps)
        Analytics.event("upload.enqueued", properties: enqueueProps)
        let task = Task { await process(item: item, pane: pane, compress: compress) }
        runningTasks[item.id] = task
    }

    func cancel(id: UUID) {
        runningTasks[id]?.cancel()
        runningTasks.removeValue(forKey: id)
        update(id: id) {
            $0.state = .cancelled
            $0.speedBytesPerSec = nil
        }
    }

    private func process(item: UploadItem, pane: Pane, compress: Bool) async {
        var item = item
        var lastSample: (date: Date, progress: Double)? = nil
        var smoothedSpeed: Double = 0

        defer {
            runningTasks.removeValue(forKey: item.id)
            if item.didCompress { VideoCompressor.discard(item.fileURL) }
        }

        do {
            if compress {
                try await runCompression(on: &item, pane: pane)
            }

            update(id: item.id) { $0.state = .uploading(progress: 0.0) }
            let uploader = S3Uploader()
            let fileSize = item.fileSize
            let itemId = item.id
            let result = try await uploader.upload(item: item, pane: pane) { progress in
                Task { @MainActor in
                    let now = Date()
                    if let prev = lastSample {
                        let dt = now.timeIntervalSince(prev.date)
                        let dp = max(0, progress - prev.progress)
                        if dt > 0.05 {
                            let instant = (dp * Double(fileSize)) / dt
                            smoothedSpeed = smoothedSpeed == 0 ? instant : (smoothedSpeed * 0.7 + instant * 0.3)
                            lastSample = (now, progress)
                        }
                    } else {
                        lastSample = (now, progress)
                    }
                    self.update(id: itemId) {
                        $0.state = .uploading(progress: progress)
                        $0.speedBytesPerSec = smoothedSpeed > 0 ? smoothedSpeed : nil
                    }
                }
            }
            update(id: item.id) {
                $0.state = .succeeded(url: result.url)
                $0.remoteKey = result.key
                $0.publicURL = result.url
                $0.speedBytesPerSec = nil
            }
            HistoryStore.shared.record(item: items.first { $0.id == item.id } ?? item, pane: pane)
            NotificationManager.shared.notifySuccess(url: result.url, fileName: item.fileName)
            let successProps: [String: Any] = [
                "pane": pane.name,
                "sizeBytes": item.fileSize,
                "compressed": item.didCompress
            ]
            Telemetry.event("upload.succeeded", data: successProps)
            Analytics.event("upload.succeeded", properties: successProps)
            scheduleAutoDismiss(id: item.id)
        } catch is CancellationError {
            // State already set to .cancelled by cancel(id:); just clean up speed.
            update(id: item.id) { $0.speedBytesPerSec = nil }
            Telemetry.event("upload.cancelled", data: ["pane": pane.name])
            Analytics.event("upload.cancelled", properties: ["pane": pane.name])
        } catch {
            update(id: item.id) {
                $0.state = .failed(message: error.localizedDescription)
                $0.speedBytesPerSec = nil
            }
            NotificationManager.shared.notifyFailure(fileName: item.fileName, message: error.localizedDescription)
            Telemetry.capture(error, context: [
                "pane": pane.name,
                "sizeBytes": item.fileSize,
                "stage": "upload"
            ])
            Analytics.event("upload.failed", properties: [
                "pane": pane.name,
                "sizeBytes": item.fileSize,
                "error": String(describing: type(of: error))
            ])
        }
    }

    /// Re-encodes to H.265 and points `item` at the result. A file that fails to
    /// shrink (already H.265, or too short to amortise the container) is dropped
    /// and the original goes up instead, so this never makes an upload worse.
    private func runCompression(on item: inout UploadItem, pane: Pane) async throws {
        update(id: item.id) { $0.state = .compressing(progress: 0.0) }
        let itemId = item.id
        let originalSize = item.originalFileSize

        do {
            let compressed = try await VideoCompressor.compress(source: item.fileURL) { progress in
                Task { @MainActor in
                    self.update(id: itemId) { $0.state = .compressing(progress: progress) }
                }
            }
            let newSize = VideoCompressor.size(of: compressed)
            guard newSize > 0, newSize < originalSize else {
                VideoCompressor.discard(compressed)
                Analytics.event("compress.skipped", properties: ["reason": "not_smaller"])
                return
            }
            item.adoptCompressed(compressed, size: newSize)
            update(id: itemId) { $0.adoptCompressed(compressed, size: newSize) }
            Analytics.event("compress.succeeded", properties: [
                "pane": pane.name,
                "originalBytes": originalSize,
                "compressedBytes": newSize
            ])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Compression is an optimisation, never a reason to lose an upload.
            Telemetry.capture(error, context: ["pane": pane.name, "stage": "compress"])
            Analytics.event("compress.failed", properties: [
                "error": String(describing: type(of: error))
            ])
        }
    }

    func dismiss(id: UUID) {
        items.removeAll { $0.id == id }
    }

    private func scheduleAutoDismiss(id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if let item = items.first(where: { $0.id == id }),
               case .succeeded = item.state {
                items.removeAll { $0.id == id }
            }
        }
    }

    private func update(id: UUID, mutate: (inout UploadItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }

    func clearFinished() {
        items.removeAll { $0.state.isTerminal }
    }
}
