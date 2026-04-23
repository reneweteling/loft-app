import Foundation
import PostHog

/// Product analytics via PostHog. Sentry handles crashes/errors; this handles
/// "which pane is hot, how often do uploads run, what's the active-user trend".
///
/// Shares the `AppConfig.analyticsEnabled` toggle with Sentry — flipping the
/// opt-out off stops both stacks at once.
///
/// The project token is a public ingest key (safe to embed in the client) and
/// is scoped to event capture only. Rotating it only requires editing this file.
enum Analytics {
    private static let projectKey = "phc_mPXSh3Dk9gDnJ94YRwSt2LBdZVpfUDvCZczTnW9Xp9Kp"
    private static let host = "https://us.i.posthog.com"
    private static var started = false

    @MainActor
    static func startIfEnabled() {
        let enabled = AppConfig.shared.analyticsEnabled
        if enabled {
            guard !started else { return }
            let config = PostHogConfig(apiKey: projectKey, host: host)
            config.captureApplicationLifecycleEvents = true
            config.captureScreenViews = false           // menu-bar app — no routing
            config.flushAt = 20
            config.flushIntervalSeconds = 30
            // Don't attach OS usernames / IPs / install UUIDs to events.
            // We want aggregate usage, not per-user attribution.
            config.sendFeatureFlagEvent = false
            PostHogSDK.shared.setup(config)
            PostHogSDK.shared.register([
                "app_version": appVersion,
                "build_type": buildType
            ])
            started = true
        } else if started {
            PostHogSDK.shared.close()
            started = false
        }
    }

    static func event(_ name: String, properties: [String: Any] = [:]) {
        guard started else { return }
        PostHogSDK.shared.capture(name, properties: properties)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private static var buildType: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}
