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
            Section("Notifications") {
                Toggle("Play sound on upload", isOn: $config.notificationSound)
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
