import Foundation
import SwiftUI

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let fileName: String
    let fileSize: Int64
    let paneName: String
    let url: URL
    let key: String
    let uploadedAt: Date
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    private let maxEntries = 100
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Loft", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func record(item: UploadItem, pane: Pane) {
        guard let url = item.publicURL, let key = item.remoteKey else { return }
        let entry = HistoryEntry(id: item.id,
                                 fileName: item.fileName,
                                 fileSize: item.fileSize,
                                 paneName: pane.name,
                                 url: url,
                                 key: key,
                                 uploadedAt: Date())
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.iso.decode([HistoryEntry].self, from: data) else {
            return
        }
        self.entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder.iso.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
