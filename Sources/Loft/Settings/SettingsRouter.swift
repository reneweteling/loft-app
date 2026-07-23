import SwiftUI
import AppKit

enum SettingsTab: String {
    case general, panes, s3, about
}

/// Opens the SwiftUI "settings" Window scene from AppKit code (the status item
/// menu). AppKit has no access to @Environment(\.openWindow), so the request is
/// posted as a notification and picked up by SettingsOpenerBridge, a hidden
/// hosting view that lives in the status bar window.
@MainActor
enum SettingsRouter {
    /// Tab to select once the settings window is (re)opened. Consumed by
    /// SettingsView; survives the gap between posting and window creation.
    static var pendingTab: SettingsTab?

    static func open(tab: SettingsTab? = nil) {
        pendingTab = tab
        NotificationCenter.default.post(name: .loftOpenSettings, object: nil)
    }
}

extension Notification.Name {
    static let loftOpenSettings = Notification.Name("com.weteling.loft.openSettings")
}

struct SettingsOpenerBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .loftOpenSettings)) { _ in
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
    }
}
