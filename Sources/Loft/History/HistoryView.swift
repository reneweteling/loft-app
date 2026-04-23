import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var history = HistoryStore.shared
    @State private var searchText = ""
    @State private var copiedId: UUID?

    private var filtered: [HistoryEntry] {
        guard !searchText.isEmpty else { return history.entries }
        let q = searchText.lowercased()
        return history.entries.filter {
            $0.fileName.lowercased().contains(q) || $0.paneName.lowercased().contains(q)
        }
    }

    var body: some View {
        if history.entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("No uploads yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { entry in
                            HistoryRow(entry: entry, copiedId: $copiedId)
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    @Binding var copiedId: UUID?
    @State private var hovered = false

    private var isCopied: Bool { copiedId == entry.id }

    private var caption: String {
        let size = ByteCountFormatter.string(fromByteCount: entry.fileSize, countStyle: .file)
        return "\(entry.paneName) · \(size) · \(relativeDate)"
    }

    private var relativeDate: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: entry.uploadedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if hovered {
                HStack(spacing: 10) {
                    Button(action: copyURL) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.clipboard")
                            .foregroundStyle(isCopied ? .green : .primary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy URL")

                    Button(action: openURL) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .help("Open in browser")

                    Button(action: removeEntry) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from history")
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(hovered ? Color.secondary.opacity(0.06) : Color.clear)
        .onHover { hovered = $0 }
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
        copiedId = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if copiedId == entry.id { copiedId = nil }
        }
    }

    private func openURL() {
        NSWorkspace.shared.open(entry.url)
    }

    private func removeEntry() {
        HistoryStore.shared.remove(entry)
    }
}
