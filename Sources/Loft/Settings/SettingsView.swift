import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var config: AppConfig

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            PanesSettingsView()
                .tabItem { Label("Panes", systemImage: "square.grid.2x2") }
            S3SettingsView()
                .tabItem { Label("S3", systemImage: "key") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(16)
    }
}
