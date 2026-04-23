import Foundation

enum UploadState: Equatable {
    case queued
    case uploading(progress: Double)
    case succeeded(url: URL)
    case failed(message: String)
    case cancelled

    var progress: Double {
        if case .uploading(let p) = self { return p }
        if case .succeeded = self { return 1.0 }
        return 0.0
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: return true
        default: return false
        }
    }
}

struct UploadItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    let paneId: UUID
    let startedAt: Date
    var state: UploadState = .queued
    var remoteKey: String?
    var publicURL: URL?
    var speedBytesPerSec: Double?

    init(fileURL: URL, paneId: UUID) {
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        self.fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        self.paneId = paneId
        self.startedAt = Date()
    }
}
