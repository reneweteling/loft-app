import Foundation
import Sentry

enum Telemetry {
    private static let dsn = "https://ec89cc6c55988f5bf280b53ecf98f654@o157871.ingest.us.sentry.io/4511268741644288"
    private static var started = false

    /// Call once on app launch. Honors the user's opt-out and starts Sentry
    /// only when analytics are enabled. Safe to call again after the user
    /// flips the toggle.
    @MainActor
    static func startIfEnabled() {
        let enabled = AppConfig.shared.analyticsEnabled
        if enabled {
            guard !started else { return }
            SentrySDK.start { options in
                options.dsn = dsn
                options.releaseName = "loft@\(Self.appVersion)"
                options.environment = Self.environment
                options.enableAutoSessionTracking = true
                options.sessionTrackingIntervalMillis = 30_000
                options.sendDefaultPii = false
                options.tracesSampleRate = 0.2
                options.enableAppHangTracking = true
                options.enableCrashHandler = true
                options.attachStacktrace = true
                options.maxBreadcrumbs = 50
            }
            SentrySDK.configureScope { scope in
                scope.setTag(value: Self.appVersion, key: "app.version")
                scope.setTag(value: Self.environment, key: "build.type")
            }
            started = true
        } else if started {
            SentrySDK.close()
            started = false
        }
    }

    /// Log a lightweight usage breadcrumb. Produces Sentry breadcrumbs only
    /// (no events), so it's cheap and doesn't consume the error quota.
    static func event(_ name: String, data: [String: Any] = [:]) {
        guard started else { return }
        let crumb = Breadcrumb()
        crumb.level = .info
        crumb.category = "usage"
        crumb.message = name
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)
    }

    /// Capture a non-fatal error with context. The Sentry SDK already catches
    /// crashes and unhandled exceptions — use this for handled failures we
    /// want to see in the dashboard (e.g. upload errors).
    static func capture(_ error: Error, context: [String: Any] = [:]) {
        guard started else { return }
        SentrySDK.capture(error: error) { scope in
            if !context.isEmpty {
                scope.setContext(value: context, key: "loft")
            }
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private static var environment: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}
