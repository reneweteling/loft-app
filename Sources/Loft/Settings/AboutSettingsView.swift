import SwiftUI
import AppKit

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(hex: "2E7CF6"), Color(hex: "8A3FFC")],
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

                Divider().padding(.horizontal, 40)

                VStack(spacing: 10) {
                    if let logo = Self.weterlingLogo {
                        Image(nsImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 44)
                            .colorInvertedIfDark()
                    }
                    VStack(spacing: 2) {
                        Text("René Weteling")
                            .font(.headline)
                        Text("Felobo B.V. · Tech Lead & Fullstack Developer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 18) {
                        LinkButton(systemImage: "globe", label: "weteling.com",
                                   url: URL(string: "https://www.weteling.com")!)
                        LinkButton(systemImage: "chevron.left.slash.chevron.right", label: "reneweteling",
                                   url: URL(string: "https://github.com/reneweteling")!)
                        LinkButton(systemImage: "envelope", label: "rene@weteling.com",
                                   url: URL(string: "mailto:rene@weteling.com")!)
                    }
                }

                Divider().padding(.horizontal, 40)

                Text("© \(Self.year) Felobo B.V.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var year: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f.string(from: Date())
    }

    static var weterlingLogo: NSImage? {
        guard let url = Bundle.module.url(forResource: "weteling-logo", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}

private extension View {
    @ViewBuilder
    func colorInvertedIfDark() -> some View {
        modifier(DarkInvertModifier())
    }
}

private struct DarkInvertModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.colorInvert()
        } else {
            content
        }
    }
}

private struct LinkButton: View {
    let systemImage: String
    let label: String
    let url: URL
    @State private var hover = false

    var body: some View {
        Button(action: { NSWorkspace.shared.open(url) }) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption)
                Text(label).font(.caption)
            }
            .foregroundStyle(hover ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
