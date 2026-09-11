import Foundation

/// Which channel this binary ships through. Decided at compile time: the
/// Xcode project (project.yml) defines APP_STORE for the store target, the
/// SwiftPM build behind the GitHub releases does not.
///
/// The two builds share everything except what App Review or the sandbox
/// rule out for the store copy, and each of those is a property here so
/// the call sites read as policy rather than as `#if` noise.
enum Distribution: Equatable {
    case github
    case appStore

    static let current: Distribution = {
        #if APP_STORE
        return .appStore
        #else
        return .github
        #endif
    }()

    /// Shown next to the version on the About tab and prefilled into bug reports.
    var label: String {
        switch self {
        case .github: return "GitHub build"
        case .appStore: return "App Store edition"
        }
    }

    /// Value of the `channel` tag on Sentry events and PostHog super-properties.
    var analyticsValue: String {
        switch self {
        case .github: return "github"
        case .appStore: return "appstore"
        }
    }

    /// The store delivers updates itself. Polling GitHub and offering a free
    /// download from inside the store copy is exactly what App Review rejects.
    var checksGitHubForUpdates: Bool { self == .github }

    /// Quick Actions are written to ~/Library/Services, which is outside the
    /// sandbox container the store copy runs in.
    var installsFinderQuickActions: Bool { self == .github }

    /// Apple ID of the app record in App Store Connect, known once the record
    /// exists. The "Rate Loft" button stays hidden while this is nil.
    static let appStoreID: String? = nil

    /// Prefilled bug report on GitHub. Issue forms accept their field ids as
    /// query parameters, so the version and channel arrive without typing.
    static func bugReportURL() -> URL {
        var components = URLComponents(string: "https://github.com/reneweteling/loft-app/issues/new")!
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug.yml"),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "macos", value: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
            URLQueryItem(name: "channel", value: current == .appStore ? "Mac App Store" : "GitHub release")
        ]
        return components.url!
    }

    static func rateURL() -> URL? {
        guard let id = appStoreID else { return nil }
        return URL(string: "macappstore://apps.apple.com/app/id\(id)?action=write-review")
    }
}
