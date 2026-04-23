import AppKit
import Foundation

func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
    func strip(_ s: String) -> String { s.hasPrefix("v") ? String(s.dropFirst()) : s }
    func components(_ s: String) -> [Int] {
        var parts = strip(s).split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        return parts
    }
    let ac = components(a)
    let bc = components(b)
    for i in 0..<3 {
        if ac[i] < bc[i] { return .orderedAscending }
        if ac[i] > bc[i] { return .orderedDescending }
    }
    return .orderedSame
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseURL: URL?
    @Published private(set) var isUpdateAvailable: Bool = false

    private let repo = "reneweteling/loft-app"
    private let minCheckInterval: TimeInterval = 24 * 3600
    private let userDefaultsKey = "loft.lastUpdateCheck"

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    func checkIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: userDefaultsKey)
        let now = Date().timeIntervalSince1970
        guard now - last >= minCheckInterval else { return }
        await performCheck()
    }

    func forceCheck() async {
        await performCheck()
    }

    func openReleasesPage() {
        let target = releaseURL ?? URL(string: "https://github.com/\(repo)/releases/latest")!
        NSWorkspace.shared.open(target)
    }

    private func performCheck() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(Release.self, from: data)
            let tag = release.tag_name
            let pageURL = URL(string: release.html_url)
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            let newer = compareSemver(tag, current) == .orderedDescending
            latestVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            releaseURL = pageURL
            isUpdateAvailable = newer
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: userDefaultsKey)
        } catch {
        }
    }
}
