import Foundation

/// The `loft://upload?pane=<uuid>&f=<hex>&f=<hex>` URL that Finder Quick
/// Actions use to hand files to the app (see ``FinderQuickActions``).
///
/// Paths travel hex-encoded rather than percent-encoded: the shell side is
/// then a `printf | od` one-liner with no quoting rules to get wrong, and any
/// byte sequence a file name can contain survives the trip. The pane id is a
/// random UUID from panes.json, so a web page cannot guess a valid URL and
/// trigger an upload of a local file behind the user's back.
enum UploadURL {
    static let scheme = "loft"
    static let host = "upload"

    struct Request: Equatable {
        let paneID: UUID
        let files: [URL]
    }

    static func parse(_ url: URL) -> Request? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let paneValue = items.first(where: { $0.name == "pane" })?.value,
              let paneID = UUID(uuidString: paneValue) else {
            return nil
        }
        let files = items
            .filter { $0.name == "f" }
            .compactMap { $0.value.flatMap(decodeHex) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
        guard !files.isEmpty else { return nil }
        return Request(paneID: paneID, files: files)
    }

    /// The inverse of ``parse(_:)``, matching what the Quick Action script emits.
    static func build(paneID: UUID, files: [URL]) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "pane", value: paneID.uuidString)]
            + files.map { URLQueryItem(name: "f", value: encodeHex($0.path)) }
        return components.url!
    }

    static func encodeHex(_ path: String) -> String {
        path.utf8.map { String(format: "%02x", $0) }.joined()
    }

    static func decodeHex(_ hex: String) -> String? {
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
