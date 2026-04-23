import Foundation

struct S3UploadResult {
    let key: String
    let url: URL
}

enum S3UploadError: LocalizedError {
    case notConfigured
    case missingCredentials
    case httpError(Int, String)
    case network(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Bucket or region not configured."
        case .missingCredentials: return "AWS credentials missing in Keychain."
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .network(let e): return "Network error: \(e.localizedDescription)"
        case .invalidResponse: return "Invalid S3 response."
        }
    }
}

/// Uploads a single file to S3 using SigV4-signed PUT.
/// Multipart upload is handled by ``MultipartUploader``; this type delegates when file > 5 MB.
struct S3Uploader {
    private static let multipartThreshold: Int64 = 5 * 1024 * 1024 // 5 MB

    @MainActor
    func upload(item: UploadItem,
                pane: Pane,
                progress: @Sendable @escaping (Double) -> Void) async throws -> S3UploadResult {
        let config = AppConfig.shared
        guard !config.bucket.isEmpty else { throw S3UploadError.notConfigured }
        guard let accessKey = KeychainStore.accessKey(),
              let secretKey = KeychainStore.secretKey() else {
            throw S3UploadError.missingCredentials
        }

        let region = config.region
        let bucket = pane.bucket ?? config.bucket
        let endpoint = config.endpoint.isEmpty ? nil : config.endpoint
        let forcePathStyle = config.forcePathStyle || endpoint != nil
        let cdn = config.cdnBaseURL.isEmpty ? nil : config.cdnBaseURL

        let key = URLBuilder.makeObjectKey(for: item.fileName, prefix: pane.keyPrefix)

        let builder = URLBuilder(region: region,
                                 bucket: bucket,
                                 endpointOverride: endpoint,
                                 forcePathStyle: forcePathStyle,
                                 cdnBaseURL: cdn)

        let tags = [
            "app": "loft",
            "ttl": pane.ttl.tagValue,
            "uploaded_at": "\(Int(Date().timeIntervalSince1970))"
        ]

        let credentials = SigV4Credentials(accessKeyId: accessKey, secretAccessKey: secretKey)

        if item.fileSize > Self.multipartThreshold {
            let multipart = MultipartUploader(credentials: credentials,
                                              region: region,
                                              bucket: bucket,
                                              urlBuilder: builder)
            try await multipart.upload(fileURL: item.fileURL,
                                       key: key,
                                       contentType: MIMEType.forFile(name: item.fileName),
                                       cacheControl: cacheControl(for: pane),
                                       acl: pane.visibility == .public ? "public-read" : nil,
                                       tags: tags,
                                       progress: progress)
        } else {
            let single = SingleObjectUploader(credentials: credentials,
                                              region: region,
                                              bucket: bucket,
                                              urlBuilder: builder)
            try await single.upload(fileURL: item.fileURL,
                                    key: key,
                                    contentType: MIMEType.forFile(name: item.fileName),
                                    cacheControl: cacheControl(for: pane),
                                    acl: pane.visibility == .public ? "public-read" : nil,
                                    tags: tags,
                                    progress: progress)
        }

        let url = try builder.outputURL(forKey: key,
                                        visibility: pane.visibility,
                                        credentials: credentials,
                                        presignExpirySeconds: pane.visibility == .private ? 7 * 86400 : nil)

        return S3UploadResult(key: key, url: url)
    }

    private func cacheControl(for pane: Pane) -> String? {
        switch pane.visibility {
        case .public: return "public, max-age=31536000, immutable"
        case .private: return "private, no-store"
        }
    }
}
