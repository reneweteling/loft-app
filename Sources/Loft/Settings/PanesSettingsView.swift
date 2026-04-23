import SwiftUI

struct PanesSettingsView: View {
    @EnvironmentObject var config: AppConfig
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            List(selection: $selection) {
                ForEach(config.panes.sorted { $0.order < $1.order }) { pane in
                    HStack {
                        Image(systemName: pane.iconSystemName)
                            .foregroundStyle(Color(hex: pane.tintHex))
                        VStack(alignment: .leading) {
                            Text(pane.name)
                            Text(pane.ttl.humanLabel).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !pane.enabled {
                            Image(systemName: "eye.slash").foregroundStyle(.secondary)
                        }
                    }
                    .tag(pane.id)
                }
            }
            .frame(minWidth: 200)

            if let selected = selectedPane {
                editor(for: selected)
                    .frame(minWidth: 280)
            } else {
                Text("Select a pane").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minHeight: 320)
    }

    private var selectedPane: Pane? {
        guard let id = selection else { return nil }
        return config.panes.first { $0.id == id }
    }

    private func editor(for pane: Pane) -> some View {
        let binding = Binding<Pane>(
            get: { pane },
            set: { updated in
                if let idx = config.panes.firstIndex(where: { $0.id == pane.id }) {
                    config.panes[idx] = updated
                }
            }
        )
        return Form {
            Section("Display") {
                TextField("Name", text: binding.name)
                TextField("SF Symbol", text: binding.iconSystemName)
                TextField("Tint hex", text: binding.tintHex)
                Toggle("Enabled", isOn: binding.enabled)
            }
            Section("Behavior") {
                Picker("TTL", selection: Binding<String>(
                    get: { pane.ttl.tagValue },
                    set: { newValue in
                        var updated = pane
                        switch newValue {
                        case "none": updated.ttl = .none
                        case "1d": updated.ttl = .days(1)
                        case "30d": updated.ttl = .days(30)
                        default: updated.ttl = .none
                        }
                        if let idx = config.panes.firstIndex(where: { $0.id == pane.id }) {
                            config.panes[idx] = updated
                        }
                    }
                )) {
                    Text("No expiry").tag("none")
                    Text("1 day").tag("1d")
                    Text("30 days").tag("30d")
                }
                Picker("Visibility", selection: binding.visibility) {
                    Text("Public").tag(Visibility.public)
                    Text("Private (presigned URL)").tag(Visibility.private)
                }
                TextField("Key prefix", text: binding.keyPrefix)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }
}
