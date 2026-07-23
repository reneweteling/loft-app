import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var config: AppConfig
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            PanesSettingsView()
                .tabItem { Label("Panes", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.panes)
            S3SettingsView()
                .tabItem { Label("S3", systemImage: "key") }
                .tag(SettingsTab.s3)
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .padding(16)
        .onAppear { consumePendingTab() }
        .onReceive(NotificationCenter.default.publisher(for: .loftOpenSettings)) { _ in
            consumePendingTab()
        }
    }

    private func consumePendingTab() {
        if let tab = SettingsRouter.pendingTab {
            selectedTab = tab
            SettingsRouter.pendingTab = nil
        }
    }
}
