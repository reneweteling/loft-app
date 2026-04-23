import Foundation
import SwiftUI

@MainActor
final class UploadQueue: ObservableObject {
    static let shared = UploadQueue()

    @Published var items: [UploadItem] = []
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    var isActive: Bool {
        items.contains { !$0.state.isTerminal }
    }

    func enqueue(fileURLs: [URL], pane: Pane) {
        for url in fileURLs {
            let item = UploadItem(fileURL: url, paneId: pane.id)
            items.append(item)
            Telemetry.event("upload.enqueued", data: [
                "pane": pane.name,
                "ttl": pane.ttl.tagValue,
                "visibility": pane.visibility.rawValue,
                "sizeBytes": item.fileSize
            ])
            let task = Task { await process(item: item, pane: pane) }
            runningTasks[item.id] = task
        }
    }

    func cancel(id: UUID) {
        runningTasks[id]?.cancel()
        runningTasks.removeValue(forKey: id)
        update(id: id) {
            $0.state = .cancelled
            $0.speedBytesPerSec = nil
        }
    }

    private func process(item: UploadItem, pane: Pane) async {
        update(id: item.id) { $0.state = .uploading(progress: 0.0) }
        var lastSample: (date: Date, progress: Double)? = nil
        var smoothedSpeed: Double = 0

        defer { runningTasks.removeValue(forKey: item.id) }

        do {
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
            Telemetry.event("upload.succeeded", data: [
                "pane": pane.name,
                "sizeBytes": item.fileSize
            ])
            scheduleAutoDismiss(id: item.id)
        } catch is CancellationError {
            // State already set to .cancelled by cancel(id:); just clean up speed.
            update(id: item.id) { $0.speedBytesPerSec = nil }
            Telemetry.event("upload.cancelled", data: ["pane": pane.name])
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
