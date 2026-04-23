import SwiftUI
import AppKit

struct AboutSettingsView: View {
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                loftHeader
                updatesRow
                Divider().padding(.horizontal, 40)
                builtByCard
                Text("© \(Self.year) Felobo B.V.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
        .task {
            await updates.checkIfNeeded()
        }
    }

    private var updatesRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if updates.isChecking {
                    ProgressView().controlSize(.small)
                    Text("Checking for updates…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if updates.isUpdateAvailable, let latest = updates.latestVersion {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Update available: v\(latest)")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Button("Download") {
                        updates.openReleasesPage()
                    }
                    .controlSize(.small)
                } else if updates.lastCheckedAt != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("You're on the latest version")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Update status unknown")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    Task { await updates.forceCheck() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(updates.isChecking)
                .help("Check for updates")
            }

            if let err = updates.lastCheckError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var loftHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex: "0EA5E9"), Color(hex: "1E3A8A")],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
            VStack(spacing: 2) {
                Text("Loft").font(.title2.weight(.semibold))
                Text("v\(Self.version)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Native macOS menu bar uploader for S3 and S3-compatible endpoints.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var builtByCard: some View {
        VStack(spacing: 14) {
            Text("BUILT BY")
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.secondary)

            if let logo = Self.weterlingLogo {
                Image(nsImage: logo)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(height: 72)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 3) {
                Text("René Weteling")
                    .font(.title3.weight(.semibold))
                Text("Felobo B.V.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Tech Lead · Fullstack · Ruby · Elixir · TypeScript")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                PillLinkButton(systemImage: "globe", label: "weteling.com",
                               url: URL(string: "https://www.weteling.com")!)
                PillLinkButton(systemImage: "chevron.left.slash.chevron.right", label: "reneweteling",
                               url: URL(string: "https://github.com/reneweteling")!)
                PillLinkButton(systemImage: "envelope", label: "Email",
                               url: URL(string: "mailto:rene@weteling.com")!)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var year: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f.string(from: Date())
    }

    static let weterlingLogo: NSImage? = {
        guard let url = Bundle.module.url(forResource: "weteling-logo", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        let intrinsic = image.size
        if intrinsic.width > 0, intrinsic.height > 0 {
            let targetHeight: CGFloat = 144
            let scale = targetHeight / intrinsic.height
            image.size = NSSize(width: intrinsic.width * scale, height: targetHeight)
        }
        image.isTemplate = true
        return image
    }()
}

private struct PillLinkButton: View {
    let systemImage: String
    let label: String
    let url: URL
    @State private var hover = false

    var body: some View {
        Button(action: { NSWorkspace.shared.open(url) }) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.caption2)
                Text(label).font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(hover ? Color.white : .primary)
            .background(
                Capsule().fill(hover ? Color.accentColor : Color.secondary.opacity(0.14))
            )
            .overlay(
                Capsule().strokeBorder(Color.secondary.opacity(hover ? 0 : 0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
