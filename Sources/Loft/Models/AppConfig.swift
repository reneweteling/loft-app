import Foundation
import SwiftUI

@MainActor
final class AppConfig: ObservableObject {
    static let shared = AppConfig()

    @AppStorage("aws.region") var region: String = "us-east-1"
    @AppStorage("aws.bucket") var bucket: String = ""
    @AppStorage("aws.endpoint") var endpoint: String = ""
    @AppStorage("aws.forcePathStyle") var forcePathStyle: Bool = false
    @AppStorage("cdn.baseURL") var cdnBaseURL: String = ""
    @AppStorage("general.launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("general.notificationSound") var notificationSound: Bool = true

    @Published var panes: [Pane] = Pane.defaults {
        didSet { persistPanes() }
    }

    private let panesURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Loft", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("panes.json")
    }()

    private init() {
        loadPanes()
    }

    private func loadPanes() {
        guard let data = try? Data(contentsOf: panesURL),
              let decoded = try? JSONDecoder().decode([Pane].self, from: data),
              !decoded.isEmpty else {
            return
        }
        self.panes = decoded
    }

    private func persistPanes() {
        guard let data = try? JSONEncoder().encode(panes) else { return }
        try? data.write(to: panesURL)
    }

    var isConfigured: Bool {
        !bucket.isEmpty && KeychainStore.hasCredentials()
    }
}
