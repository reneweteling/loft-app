import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @EnvironmentObject var config: AppConfig
    @State private var launchAtLoginStatus: String = ""

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { config.launchAtLogin },
                    set: { newValue in
                        config.launchAtLogin = newValue
                        applyLaunchAtLogin(newValue)
                    }
                ))
                if !launchAtLoginStatus.isEmpty {
                    Text(launchAtLoginStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Privacy") {
                Toggle("Share anonymous crash reports and usage", isOn: Binding(
                    get: { config.analyticsEnabled },
                    set: { newValue in
                        config.analyticsEnabled = newValue
                        Telemetry.startIfEnabled()
                    }
                ))
                Text("Sends crash reports and aggregated usage counts (uploads per pane, file sizes) to Sentry. No file names, URLs, credentials, or personal data are transmitted. Toggle off to disable entirely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Show system notifications", isOn: Binding(
                    get: { config.showSystemNotifications },
                    set: { newValue in
                        config.showSystemNotifications = newValue
                        if newValue {
                            Task { await NotificationManager.shared.requestAuthorizationIfOptedIn() }
                        }
                    }
                ))
                Toggle("Play sound on upload", isOn: $config.notificationSound)
                    .disabled(!config.showSystemNotifications)
                Text("Upload URLs are always copied to the clipboard. System notifications are optional — macOS will ask permission the first time you enable them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { syncLaunchAtLoginStatus() }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                launchAtLoginStatus = "Registered as login item."
            } else {
                try SMAppService.mainApp.unregister()
                launchAtLoginStatus = "Removed from login items."
            }
        } catch {
            launchAtLoginStatus = "Failed: \(error.localizedDescription)"
        }
    }

    private func syncLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled: launchAtLoginStatus = "Currently enabled."
        case .notRegistered: launchAtLoginStatus = ""
        case .requiresApproval: launchAtLoginStatus = "Approval needed in System Settings → General → Login Items."
        case .notFound: launchAtLoginStatus = ""
        @unknown default: launchAtLoginStatus = ""
        }
    }
}
