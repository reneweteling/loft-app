import SwiftUI
import AppKit

struct PopoverView: View {
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var uploadQueue: UploadQueue
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: Tab = .drop
    @State private var updateDismissed: Bool = false

    enum Tab: String, CaseIterable { case drop = "Drop", history = "History" }

    private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if updates.isUpdateAvailable && !updateDismissed {
                updateBanner
            }
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack {
            Image(systemName: "arrow.up.circle.fill").font(.system(size: 16))
            Text("Loft").font(.headline)
            Spacer()
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var updateBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color(hex: "0EA5E9"))
            Text("Update available: \(updates.latestVersion ?? "")")
                .font(.caption)
            Spacer()
            Button("Download") { updates.openReleasesPage() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color(hex: "0EA5E9"))
            Button {
                updateDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "0EA5E9").opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(hex: "0EA5E9").opacity(0.6), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        if !config.isConfigured {
            setupPrompt
        } else {
            switch selectedTab {
            case .drop: dropGrid
            case .history: HistoryView().environmentObject(config)
            }
        }
    }

    private var setupPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "gear").font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Set up AWS credentials first")
                .font(.headline)
            Text("Open settings (⌘,) to add your access key, secret, and bucket.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") { openSettings() }
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 88), spacing: 10)]
        return VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(config.panes.filter { $0.enabled }) { pane in
                    DropPaneView(pane: pane)
                }
            }
            .padding(12)

            if !uploadQueue.items.isEmpty {
                Divider().padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(uploadQueue.items) { item in
                        UploadRow(item: item)
                    }
                }
                .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(config.isConfigured ? "Bucket: \(config.bucket)" : "Not configured")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { openSettings() }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct UploadRow: View {
    let item: UploadItem
    @EnvironmentObject var uploadQueue: UploadQueue

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.fileName)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                        .monospacedDigit()
                    if item.state.isTerminal {
                        Button(action: { uploadQueue.dismiss(id: item.id) }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss")
                    } else {
                        Button(action: { uploadQueue.cancel(id: item.id) }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel")
                    }
                }
                ProgressView(value: item.state.progress)
                    .progressViewStyle(.linear)
            }
        }
    }

    private var iconName: String {
        switch item.state {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .uploading: return "arrow.up.circle"
        case .queued: return "clock"
        }
    }

    private var iconColor: Color {
        switch item.state {
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        default: return .accentColor
        }
    }

    private var statusLabel: String {
        switch item.state {
        case .queued: return "queued"
        case .uploading(let p):
            let pct = "\(Int(p * 100))%"
            if let bps = item.speedBytesPerSec, bps > 0 {
                return "\(pct) · \(Self.speedFormatter.string(fromByteCount: Int64(bps)))/s"
            }
            return pct
        case .succeeded: return "done"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        }
    }

    private static let speedFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.includesUnit = true
        f.isAdaptive = true
        return f
    }()
}
