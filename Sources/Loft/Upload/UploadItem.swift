import Foundation

enum UploadState: Equatable {
    case queued
    case compressing(progress: Double)
    case uploading(progress: Double)
    case succeeded(url: URL)
    case failed(message: String)
    case cancelled

    var progress: Double {
        if case .compressing(let p) = self { return p }
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
    /// Points at the compressed temp file once compression has run, so the
    /// uploader and the S3 key both follow the file that actually goes up.
    private(set) var fileURL: URL
    private(set) var fileName: String
    private(set) var fileSize: Int64
    /// Size of the dropped file, kept so the row can show what was saved.
    let originalFileSize: Int64
    private(set) var didCompress: Bool = false
    let paneId: UUID
    let startedAt: Date
    var state: UploadState = .queued
    var remoteKey: String?
    var publicURL: URL?
    var speedBytesPerSec: Double?

    init(fileURL: URL, paneId: UUID) {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        self.fileSize = size
        self.originalFileSize = size
        self.paneId = paneId
        self.startedAt = Date()
    }

    mutating func adoptCompressed(_ url: URL, size: Int64) {
        fileURL = url
        fileName = url.lastPathComponent
        fileSize = size
        didCompress = true
    }
}
