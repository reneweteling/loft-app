import Foundation
import CryptoKit

struct SigV4Credentials: Sendable {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?

    init(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }
}

enum SigV4Error: LocalizedError {
    case invalidURL
    case unsupportedMethod
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL for signing"
        case .unsupportedMethod: return "Unsupported HTTP method for signing"
        }
    }
}

/// Minimal AWS SigV4 signer for S3 (service: "s3").
/// Supports: signed PUT/GET with a body, and presigning a GET URL.
/// Headers signed by default: host, x-amz-content-sha256, x-amz-date, plus anything the caller passes in.
enum SigV4Signer {
    static let service = "s3"
    static let algorithm = "AWS4-HMAC-SHA256"

    // MARK: - Regular request signing

    /// Sign a request in-place. Returns a dictionary of headers that must be set on the request.
    static func sign(method: String,
                     url: URL,
                     region: String,
                     credentials: SigV4Credentials,
                     bodyHash: String,
                     extraHeaders: [String: String] = [:],
                     now: Date = Date()) throws -> [String: String] {

        guard let host = url.host else { throw SigV4Error.invalidURL }

        let (amzDate, dateStamp) = formatDates(now)

        var headers: [String: String] = [
            "Host": hostHeaderValue(host: host, port: url.port),
            "x-amz-content-sha256": bodyHash,
            "x-amz-date": amzDate
        ]
        if let token = credentials.sessionToken {
            headers["x-amz-security-token"] = token
        }
        for (k, v) in extraHeaders {
            headers[k] = v
        }

        // Canonical request
        let canonicalURI = canonicalURI(for: url)
        let canonicalQuery = canonicalQueryString(for: url)
        let (canonicalHeaders, signedHeaders) = canonicalHeadersAndSignedHeaders(headers)
        let canonicalRequest = [
            method.uppercased(),
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            bodyHash
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            hexSHA256(canonicalRequest)
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(secret: credentials.secretAccessKey,
                                          dateStamp: dateStamp,
                                          region: region,
                                          service: service)
        let signature = hexHMAC(key: signingKey, data: Data(stringToSign.utf8))

        let auth = "\(algorithm) Credential=\(credentials.accessKeyId)/\(credentialScope), " +
                   "SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var out = headers
        out["Authorization"] = auth
        return out
    }

    // MARK: - Presign GET URL

    static func presignGet(url: URL,
                           region: String,
                           credentials: SigV4Credentials,
                           expiresIn: Int,
                           now: Date = Date()) throws -> URL {
        guard let host = url.host,
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SigV4Error.invalidURL
        }
        let (amzDate, dateStamp) = formatDates(now)
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"

        var queryItems = comps.queryItems ?? []
        queryItems.append(URLQueryItem(name: "X-Amz-Algorithm", value: algorithm))
        queryItems.append(URLQueryItem(name: "X-Amz-Credential", value: "\(credentials.accessKeyId)/\(credentialScope)"))
        queryItems.append(URLQueryItem(name: "X-Amz-Date", value: amzDate))
        queryItems.append(URLQueryItem(name: "X-Amz-Expires", value: "\(expiresIn)"))
        queryItems.append(URLQueryItem(name: "X-Amz-SignedHeaders", value: "host"))
        if let token = credentials.sessionToken {
            queryItems.append(URLQueryItem(name: "X-Amz-Security-Token", value: token))
        }

        comps.queryItems = queryItems.sorted { $0.name < $1.name }

        // Build canonical request for presigning
        let canonicalURI = canonicalURI(for: url)
        let canonicalQuery = canonicalQueryString(from: comps.queryItems ?? [])
        let signedHeaders = "host"
        let canonicalHeaders = "host:\(hostHeaderValue(host: host, port: url.port))\n"
        let canonicalRequest = [
            "GET",
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")

        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            hexSHA256(canonicalRequest)
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(secret: credentials.secretAccessKey,
                                          dateStamp: dateStamp,
                                          region: region,
                                          service: service)
        let signature = hexHMAC(key: signingKey, data: Data(stringToSign.utf8))

        queryItems.append(URLQueryItem(name: "X-Amz-Signature", value: signature))
        // Re-sort for clean URL
        comps.queryItems = queryItems.sorted { $0.name < $1.name }
        guard let final = comps.url else { throw SigV4Error.invalidURL }
        return final
    }

    // MARK: - Helpers

    private static func hostHeaderValue(host: String, port: Int?) -> String {
        guard let port, port != 80, port != 443 else { return host }
        return "\(host):\(port)"
    }

    private static func formatDates(_ date: Date) -> (amzDate: String, dateStamp: String) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = fmt.string(from: date)
        fmt.dateFormat = "yyyyMMdd"
        let dateStamp = fmt.string(from: date)
        return (amzDate, dateStamp)
    }

    private static func canonicalURI(for url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        // Encode each segment preserving "/"
        return path.split(separator: "/", omittingEmptySubsequences: false).map { seg in
            if seg.isEmpty { return "" }
            return rfc3986Encode(String(seg))
        }.joined(separator: "/")
    }

    static func canonicalQueryString(for url: URL) -> String {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return "" }
        return canonicalQueryString(from: items)
    }

    static func canonicalQueryString(from items: [URLQueryItem]) -> String {
        let encoded = items.map { item -> (String, String) in
            let k = rfc3986Encode(item.name)
            let v = rfc3986Encode(item.value ?? "")
            return (k, v)
        }
        let sorted = encoded.sorted { a, b in
            if a.0 == b.0 { return a.1 < b.1 }
            return a.0 < b.0
        }
        return sorted.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    private static func canonicalHeadersAndSignedHeaders(_ headers: [String: String]) -> (String, String) {
        let lowered = Dictionary(uniqueKeysWithValues: headers.map {
            ($0.key.lowercased(), trimAndCollapse($0.value))
        })
        let keys = lowered.keys.sorted()
        let canonical = keys.map { "\($0):\(lowered[$0]!)\n" }.joined()
        let signed = keys.joined(separator: ";")
        return (canonical, signed)
    }

    private static func trimAndCollapse(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        return parts.joined(separator: " ")
    }

    static func hexSHA256(_ s: String) -> String {
        return hexSHA256(Data(s.utf8))
    }

    static func hexSHA256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func deriveSigningKey(secret: String, dateStamp: String, region: String, service: String) -> Data {
        let kDate = hmac(key: Data("AWS4\(secret)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmac(key: kDate, data: Data(region.utf8))
        let kService = hmac(key: kRegion, data: Data(service.utf8))
        return hmac(key: kService, data: Data("aws4_request".utf8))
    }

    private static func hmac(key: Data, data: Data) -> Data {
        let sym = SymmetricKey(data: key)
        let auth = HMAC<SHA256>.authenticationCode(for: data, using: sym)
        return Data(auth)
    }

    private static func hexHMAC(key: Data, data: Data) -> String {
        let raw = hmac(key: key, data: data)
        return raw.map { String(format: "%02x", $0) }.joined()
    }

    /// RFC 3986 unreserved: ALPHA / DIGIT / - . _ ~
    static func rfc3986Encode(_ s: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
