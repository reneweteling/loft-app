import Foundation

struct URLBuilder {
    let region: String
    let bucket: String
    let endpointOverride: String?
    let forcePathStyle: Bool
    let cdnBaseURL: String?

    /// Buckets with dots break virtual-hosted TLS: `*.s3.region.amazonaws.com` is a single-level
    /// wildcard, so `my.bucket.s3.region.amazonaws.com` fails cert validation. Fall back to path-style.
    private var effectivePathStyle: Bool {
        forcePathStyle || bucket.contains(".")
    }

    /// Host (no scheme) for the S3 API calls. Path-style keeps bucket out of the host.
    var apiHost: String {
        if let override = endpointOverride, !override.isEmpty {
            return URL(string: override)?.host ?? override.replacingOccurrences(of: "https://", with: "")
        }
        return effectivePathStyle
            ? "s3.\(region).amazonaws.com"
            : "\(bucket).s3.\(region).amazonaws.com"
    }

    /// Base URL for raw API PUT/GET, e.g. https://host[/bucket]
    func apiBaseURL() -> URL {
        let scheme = "https"
        if effectivePathStyle {
            return URL(string: "\(scheme)://\(apiHost)/\(bucket)")!
        } else {
            return URL(string: "\(scheme)://\(apiHost)")!
        }
    }

    func objectURL(key: String) -> URL {
        apiBaseURL().appendingPathComponent(key)
    }

    /// Final URL handed to the user. CDN wins if set; else raw S3; else for .private we presign.
    func outputURL(forKey key: String,
                   visibility: Visibility,
                   credentials: SigV4Credentials,
                   presignExpirySeconds: Int?) throws -> URL {
        if let cdn = cdnBaseURL, !cdn.isEmpty, visibility == .public {
            let trimmed = cdn.hasSuffix("/") ? String(cdn.dropLast()) : cdn
            let encodedKey = key.split(separator: "/").map {
                $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
            }.joined(separator: "/")
            return URL(string: "\(trimmed)/\(encodedKey)") ?? objectURL(key: key)
        }
        switch visibility {
        case .public:
            return objectURL(key: key)
        case .private:
            let seconds = presignExpirySeconds ?? 604800
            return try SigV4Signer.presignGet(url: objectURL(key: key),
                                              region: region,
                                              credentials: credentials,
                                              expiresIn: seconds)
        }
    }

    // MARK: - Key generation

    static func makeObjectKey(for filename: String, prefix: String) -> String {
        let date = Date()
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let datePath = String(format: "%04d/%02d/%02d",
                              comps.year ?? 1970,
                              comps.month ?? 1,
                              comps.day ?? 1)
        let safe = sanitize(filename: filename)
        let nano = nanoId(length: 10)
        let cleanPrefix = prefix.hasSuffix("/") ? prefix : prefix + "/"
        return "\(cleanPrefix)\(datePath)/\(nano)-\(safe)"
    }

    static func sanitize(filename: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_")
        let collapsed = filename.replacingOccurrences(of: " ", with: "-")
        let scalars = collapsed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var result = String(scalars)
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        if result.hasPrefix("-") { result.removeFirst() }
        if result.isEmpty { result = "file" }
        return result
    }

    static func nanoId(length: Int) -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var out = ""
        out.reserveCapacity(length)
        for _ in 0..<length {
            out.append(alphabet[Int.random(in: 0..<alphabet.count)])
        }
        return out
    }
}
