import Foundation

enum RetryPolicy {
    static func run<T>(maxAttempts: Int = 3,
                       initialDelay: TimeInterval = 0.5,
                       maxDelay: TimeInterval = 8,
                       shouldRetry: (Error) -> Bool = RetryPolicy.isTransient,
                       operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 1...max(1, maxAttempts) {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt == maxAttempts || !shouldRetry(error) {
                    throw error
                }
                let base = min(initialDelay * pow(2.0, Double(attempt - 1)), maxDelay)
                let jitter = Double.random(in: -0.2...0.2) * base
                let delay = max(0, base + jitter)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw lastError ?? S3UploadError.invalidResponse
    }

    static func isTransient(_ error: Error) -> Bool {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .cancelled, .userCancelledAuthentication, .userAuthenticationRequired:
                return false
            default:
                return true
            }
        }
        if let s3 = error as? S3UploadError {
            switch s3 {
            case .network:
                return true
            case .invalidResponse:
                return true
            case .httpError(let status, _):
                return [408, 429, 500, 502, 503, 504].contains(status)
            case .notConfigured, .missingCredentials:
                return false
            }
        }
        return false
    }
}
