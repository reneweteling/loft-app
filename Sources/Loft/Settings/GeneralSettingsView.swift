import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @EnvironmentObject var config: AppConfig
    @State private var launchAtLoginStatus: String = ""
    /// @AppStorage inside an ObservableObject does not publish, so the stepper
    /// label needs a local mirror to redraw as you click it.
    @State private var thresholdMB: Int = AppConfig.shared.videoCompressionThresholdMB

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
                        Analytics.startIfEnabled()
                    }
                ))
                Text("Sends crash reports (Sentry) and aggregated usage counts — uploads per pane, file sizes (PostHog). No file names, URLs, credentials, or personal data are transmitted. Toggle off to disable both.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Media") {
                Picker("Large videos", selection: $config.videoCompressionPolicy) {
                    ForEach(VideoCompressionPolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                Stepper(value: $thresholdMB, in: 1...2000, step: 5) {
                    Text("Threshold: \(thresholdMB) MB")
                }
                .onChange(of: thresholdMB) { _, newValue in
                    config.videoCompressionThresholdMB = newValue
                }
                .disabled(config.videoCompressionPolicy == .never)
                Picker("Quality", selection: $config.videoCompressionQuality) {
                    ForEach(VideoCompressionQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .disabled(config.videoCompressionPolicy == .never)
                Text("Videos above the threshold are re-encoded to H.265 at their original resolution before uploading. Encoding runs on the Apple Silicon media engine via VideoToolbox. Higher quality keeps more detail at a larger size; if the result is not smaller than the original, the original is uploaded instead.")
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
