import XCTest
@testable import Loft

final class RetryPolicyTests: XCTestCase {

    // MARK: - Helpers

    private actor Counter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    // MARK: - run(_:) behaviour

    func testSucceedsOnFirstAttempt() async throws {
        let counter = Counter()
        let result = try await RetryPolicy.run(operation: {
            await counter.increment()
            return 42
        })
        XCTAssertEqual(result, 42)
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testRetriesOnTransientError() async throws {
        let counter = Counter()
        let result = try await RetryPolicy.run(
            maxAttempts: 3,
            initialDelay: 0.01,
            maxDelay: 0.05
        ) {
            await counter.increment()
            let c = await counter.count
            if c < 3 {
                throw S3UploadError.httpError(503, "x")
            }
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        let count = await counter.count
        XCTAssertEqual(count, 3)
    }

    func testStopsAtMaxAttempts() async throws {
        let counter = Counter()
        do {
            _ = try await RetryPolicy.run(
                maxAttempts: 2,
                initialDelay: 0.01,
                maxDelay: 0.05
            ) {
                await counter.increment()
                throw S3UploadError.httpError(503, "transient")
            }
            XCTFail("Expected error to be thrown")
        } catch let error as S3UploadError {
            if case .httpError(503, _) = error { } else {
                XCTFail("Unexpected error case: \(error)")
            }
        }
        let count = await counter.count
        XCTAssertEqual(count, 2)
    }

    func testDoesNotRetryNonTransient() async throws {
        let counter = Counter()
        do {
            _ = try await RetryPolicy.run(
                maxAttempts: 3,
                initialDelay: 0.01,
                maxDelay: 0.05
            ) {
                await counter.increment()
                throw S3UploadError.httpError(403, "forbidden")
            }
            XCTFail("Expected error to be thrown")
        } catch let error as S3UploadError {
            if case .httpError(403, _) = error { } else {
                XCTFail("Unexpected error case: \(error)")
            }
        }
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    // MARK: - isTransient(_:)

    func testIsTransient_retries5xxAnd429And408() {
        for status in [500, 502, 503, 504, 429, 408] {
            XCTAssertTrue(
                RetryPolicy.isTransient(S3UploadError.httpError(status, "")),
                "Expected HTTP \(status) to be transient"
            )
        }
    }

    func testIsTransient_doesNotRetry4xx() {
        for status in [400, 401, 403, 404] {
            XCTAssertFalse(
                RetryPolicy.isTransient(S3UploadError.httpError(status, "")),
                "Expected HTTP \(status) to be non-transient"
            )
        }
    }

    func testIsTransient_networkErrorsAreTransient() {
        XCTAssertTrue(RetryPolicy.isTransient(S3UploadError.network(URLError(.timedOut))))
        XCTAssertTrue(RetryPolicy.isTransient(S3UploadError.invalidResponse))
    }

    func testIsTransient_configErrorsNotTransient() {
        XCTAssertFalse(RetryPolicy.isTransient(S3UploadError.notConfigured))
        XCTAssertFalse(RetryPolicy.isTransient(S3UploadError.missingCredentials))
    }

    func testIsTransient_URLErrorCancelledNotRetried() {
        XCTAssertFalse(RetryPolicy.isTransient(URLError(.cancelled)))
    }
}
