import SwiftUI
import UniformTypeIdentifiers

struct DropPaneView: View {
    let pane: Pane
    @EnvironmentObject var uploadQueue: UploadQueue
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: pane.iconSystemName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(
                    LinearGradient(colors: gradientColors,
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            Text(pane.name)
                .font(.caption)
                .lineLimit(1)
            Text(pane.ttl.humanLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.15),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [4]))
        )
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    private var gradientColors: [Color] {
        [Color(hex: pane.tintHex).opacity(0.95), Color(hex: pane.tintHex).opacity(0.75)]
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var fileURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                fileURLs.append(url)
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                uploadQueue.enqueue(droppedURLs: fileURLs, pane: pane)
            }
        }
        return true
    }
}

extension Color {
    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
