import Foundation

/// PUT a single file to S3 using SigV4. Best for files under multipart threshold.
struct SingleObjectUploader {
    let credentials: SigV4Credentials
    let region: String
    let bucket: String
    let urlBuilder: URLBuilder

    func upload(fileURL: URL,
                key: String,
                contentType: String,
                cacheControl: String?,
                acl: String?,
                tags: [String: String],
                progress: @Sendable @escaping (Double) -> Void) async throws {

        let data = try Data(contentsOf: fileURL)
        let url = urlBuilder.objectURL(key: key)

        var extraHeaders: [String: String] = [
            "Content-Type": contentType,
            "Content-Length": "\(data.count)"
        ]
        if let cc = cacheControl { extraHeaders["Cache-Control"] = cc }
        if let acl { extraHeaders["x-amz-acl"] = acl }
        extraHeaders["x-amz-tagging"] = encodeTags(tags)

        // Re-sign per attempt: SigV4 signatures have a 15-minute validity window.
        try await RetryPolicy.run(maxAttempts: 3) {
            try Task.checkCancellation()

            let bodyHash = SigV4Signer.hexSHA256(data)
            let signed = try SigV4Signer.sign(
                method: "PUT",
                url: url,
                region: region,
                credentials: credentials,
                bodyHash: bodyHash,
                extraHeaders: extraHeaders
            )

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            for (k, v) in signed { request.setValue(v, forHTTPHeaderField: k) }

            let delegate = SingleUploadDelegate(progress: progress)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

            do {
                let (respData, resp) = try await session.upload(for: request, from: data)
                session.finishTasksAndInvalidate()
                try Self.validate(resp: resp, data: respData)
                progress(1.0)
            } catch {
                session.invalidateAndCancel()
                throw error
            }
        }
    }

    static func validate(resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw S3UploadError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            throw S3UploadError.httpError(http.statusCode, body)
        }
    }

    private func encodeTags(_ tags: [String: String]) -> String {
        tags.map { key, value in
            let k = SigV4Signer.rfc3986Encode(key)
            let v = SigV4Signer.rfc3986Encode(value)
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

final class SingleUploadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void

    init(progress: @Sendable @escaping (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
