import Foundation

/// Multipart upload for files larger than 5 MB.
/// 16 MB parts, up to 8 concurrent uploads, HTTP/1.1 for real TCP parallelism to S3.
actor MultipartUploader {
    private let credentials: SigV4Credentials
    private let region: String
    private let bucket: String
    private let urlBuilder: URLBuilder
    private let session: URLSession

    private let partSize: Int = 16 * 1024 * 1024  // 16 MB
    private let concurrency: Int = 8

    init(credentials: SigV4Credentials, region: String, bucket: String, urlBuilder: URLBuilder) {
        self.credentials = credentials
        self.region = region
        self.bucket = bucket
        self.urlBuilder = urlBuilder

        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 3600
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        if #available(macOS 13.0, *) {
            cfg.httpAdditionalHeaders = ["Connection": "keep-alive"]
        }
        self.session = URLSession(configuration: cfg)
    }

    func upload(fileURL: URL,
                key: String,
                contentType: String,
                cacheControl: String?,
                acl: String?,
                tags: [String: String],
                progress: @Sendable @escaping (Double) -> Void) async throws {

        let fileSize = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        guard fileSize > 0 else { throw S3UploadError.invalidResponse }

        let uploadId = try await initiateMultipart(key: key,
                                                   contentType: contentType,
                                                   cacheControl: cacheControl,
                                                   acl: acl,
                                                   tags: tags)

        do {
            let parts = try await uploadParts(fileURL: fileURL,
                                              fileSize: fileSize,
                                              key: key,
                                              uploadId: uploadId,
                                              progress: progress)
            try await completeMultipart(key: key, uploadId: uploadId, parts: parts)
        } catch {
            try? await abortMultipart(key: key, uploadId: uploadId)
            throw error
        }
    }

    // MARK: - Phases

    private func initiateMultipart(key: String,
                                   contentType: String,
                                   cacheControl: String?,
                                   acl: String?,
                                   tags: [String: String]) async throws -> String {
        var comps = URLComponents(url: urlBuilder.objectURL(key: key), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "uploads", value: "")]
        let url = comps.url!

        var extraHeaders: [String: String] = [
            "Content-Type": contentType
        ]
        if let cc = cacheControl { extraHeaders["Cache-Control"] = cc }
        if let acl { extraHeaders["x-amz-acl"] = acl }
        extraHeaders["x-amz-tagging"] = tags.map { "\(SigV4Signer.rfc3986Encode($0.key))=\(SigV4Signer.rfc3986Encode($0.value))" }.joined(separator: "&")

        let signed = try SigV4Signer.sign(method: "POST",
                                          url: url,
                                          region: region,
                                          credentials: credentials,
                                          bodyHash: SigV4Signer.hexSHA256(""),
                                          extraHeaders: extraHeaders)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in signed { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await session.data(for: req)
        try SingleObjectUploader.validate(resp: resp, data: data)

        guard let xml = String(data: data, encoding: .utf8),
              let uploadId = Self.extract(tag: "UploadId", from: xml) else {
            throw S3UploadError.invalidResponse
        }
        return uploadId
    }

    private func uploadParts(fileURL: URL,
                             fileSize: Int64,
                             key: String,
                             uploadId: String,
                             progress: @Sendable @escaping (Double) -> Void) async throws -> [(partNumber: Int, eTag: String)] {
        let totalParts = Int((fileSize + Int64(partSize) - 1) / Int64(partSize))
        let progressCounter = ProgressCounter(total: totalParts, callback: progress)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        // Read sequentially, upload concurrently with bounded parallelism.
        var parts: [(Int, String)] = []
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var nextPart = 1
            var inFlight = 0

            func readNextChunk() throws -> (Int, Data)? {
                if nextPart > totalParts { return nil }
                let n = nextPart
                let chunk = try handle.read(upToCount: partSize) ?? Data()
                if chunk.isEmpty { return nil }
                nextPart += 1
                return (n, chunk)
            }

            // Prime up to `concurrency` parts
            while inFlight < concurrency, let (n, chunk) = try readNextChunk() {
                inFlight += 1
                group.addTask { [self] in
                    let etag = try await self.uploadPart(key: key, uploadId: uploadId, partNumber: n, data: chunk)
                    await progressCounter.increment()
                    return (n, etag)
                }
            }

            while let result = try await group.next() {
                parts.append(result)
                inFlight -= 1
                if let (n, chunk) = try readNextChunk() {
                    inFlight += 1
                    group.addTask { [self] in
                        let etag = try await self.uploadPart(key: key, uploadId: uploadId, partNumber: n, data: chunk)
                        await progressCounter.increment()
                        return (n, etag)
                    }
                }
            }
        }

        return parts.sorted { $0.0 < $1.0 }.map { (partNumber: $0.0, eTag: $0.1) }
    }

    private func uploadPart(key: String, uploadId: String, partNumber: Int, data: Data) async throws -> String {
        var comps = URLComponents(url: urlBuilder.objectURL(key: key), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "partNumber", value: "\(partNumber)"),
            URLQueryItem(name: "uploadId", value: uploadId)
        ]
        let url = comps.url!

        return try await RetryPolicy.run(maxAttempts: 3) {
            try Task.checkCancellation()
            let bodyHash = SigV4Signer.hexSHA256(data)
            let signed = try SigV4Signer.sign(method: "PUT",
                                              url: url,
                                              region: region,
                                              credentials: credentials,
                                              bodyHash: bodyHash,
                                              extraHeaders: ["Content-Length": "\(data.count)"])

            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            for (k, v) in signed { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = data

            let (respData, resp) = try await session.data(for: req)
            try SingleObjectUploader.validate(resp: resp, data: respData)
            guard let http = resp as? HTTPURLResponse,
                  let etag = http.value(forHTTPHeaderField: "ETag") else {
                throw S3UploadError.invalidResponse
            }
            return etag
        }
    }

    private func completeMultipart(key: String, uploadId: String, parts: [(partNumber: Int, eTag: String)]) async throws {
        var comps = URLComponents(url: urlBuilder.objectURL(key: key), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "uploadId", value: uploadId)]
        let url = comps.url!

        var xml = "<CompleteMultipartUpload>"
        for p in parts {
            xml += "<Part><PartNumber>\(p.partNumber)</PartNumber><ETag>\(p.eTag)</ETag></Part>"
        }
        xml += "</CompleteMultipartUpload>"
        let body = Data(xml.utf8)

        try await RetryPolicy.run(maxAttempts: 3) {
            let signed = try SigV4Signer.sign(method: "POST",
                                              url: url,
                                              region: region,
                                              credentials: credentials,
                                              bodyHash: SigV4Signer.hexSHA256(body),
                                              extraHeaders: [
                                                "Content-Type": "application/xml",
                                                "Content-Length": "\(body.count)"
                                              ])

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            for (k, v) in signed { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = body
            let (data, resp) = try await session.data(for: req)
            try SingleObjectUploader.validate(resp: resp, data: data)
        }
    }

    private func abortMultipart(key: String, uploadId: String) async throws {
        var comps = URLComponents(url: urlBuilder.objectURL(key: key), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "uploadId", value: uploadId)]
        let url = comps.url!
        let signed = try SigV4Signer.sign(method: "DELETE",
                                          url: url,
                                          region: region,
                                          credentials: credentials,
                                          bodyHash: SigV4Signer.hexSHA256(""))
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in signed { req.setValue(v, forHTTPHeaderField: k) }
        _ = try? await session.data(for: req)
    }

    // MARK: - XML tag extraction (tiny)

    static func extract(tag: String, from xml: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>", range: start.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[start.upperBound..<end.lowerBound])
    }
}

/// Thread-safe part-completion counter for progress reporting.
actor ProgressCounter {
    private let total: Int
    private var done: Int = 0
    private let callback: @Sendable (Double) -> Void

    init(total: Int, callback: @Sendable @escaping (Double) -> Void) {
        self.total = total
        self.callback = callback
    }

    func increment() {
        done += 1
        let p = total > 0 ? Double(done) / Double(total) : 1.0
        callback(p)
    }
}
