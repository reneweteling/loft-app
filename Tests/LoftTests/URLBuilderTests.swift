import XCTest
@testable import Loft

final class URLBuilderTests: XCTestCase {

    // MARK: - sanitize(filename:)

    func testSanitizeSpacesToDashes() {
        XCTAssertEqual(URLBuilder.sanitize(filename: "my file.txt"), "my-file.txt")
    }

    func testSanitizeAccentedCharsBecomeDashes() {
        // Accented chars are not in the allowed set, so they map to '-'
        // 'r', 'é', 's', 'u', 'm', 'é' → r-sum-.pdf, collapsed: r-sum-.pdf
        // Leading dash removed if present; consecutive dashes collapsed
        let result = URLBuilder.sanitize(filename: "résumé.pdf")
        // Accented chars → '-', then consecutive '-' collapsed
        XCTAssertFalse(result.isEmpty)
        // No accented chars should remain
        let allowedSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_-")
        XCTAssertTrue(result.unicodeScalars.allSatisfy { allowedSet.contains($0) },
                      "Should only contain allowed chars, got: \(result)")
    }

    func testSanitizeNoSlashesRemain() {
        let result = URLBuilder.sanitize(filename: "a//b")
        XCTAssertFalse(result.contains("/"), "Result should contain no slashes, got: \(result)")
    }

    func testSanitizeEmptyInputReturnsFile() {
        XCTAssertEqual(URLBuilder.sanitize(filename: ""), "file")
    }

    func testSanitizeLeadingDashStripped() {
        // A filename that starts with a space → "-something" after replacement → "something"
        let result = URLBuilder.sanitize(filename: " leading")
        XCTAssertFalse(result.hasPrefix("-"), "Leading dash should be stripped, got: \(result)")
    }

    func testSanitizeConsecutiveDashesCollapsed() {
        // Multiple spaces become multiple dashes, then collapsed
        let result = URLBuilder.sanitize(filename: "a  b")
        XCTAssertFalse(result.contains("--"), "Double dashes should be collapsed, got: \(result)")
        XCTAssertEqual(result, "a-b")
    }

    func testSanitizeAllowedCharsUnchanged() {
        XCTAssertEqual(URLBuilder.sanitize(filename: "file_name.txt"), "file_name.txt")
    }

    // MARK: - makeObjectKey(for:prefix:)

    func testMakeObjectKeyContainsPrefix() {
        let key = URLBuilder.makeObjectKey(for: "photo.jpg", prefix: "uploads")
        XCTAssertTrue(key.hasPrefix("uploads/"), "Key should start with 'uploads/', got: \(key)")
    }

    func testMakeObjectKeyStructure() {
        let key = URLBuilder.makeObjectKey(for: "photo.jpg", prefix: "uploads")
        // Expected: uploads/YYYY/MM/DD/<10-char-nano>-photo.jpg
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        // parts: ["uploads", "YYYY", "MM", "DD", "<nano>-photo.jpg"]
        XCTAssertEqual(parts.count, 5, "Key should have 5 slash-separated parts, got: \(key)")
        let lastPart = String(parts[4])
        let dashIdx = lastPart.firstIndex(of: "-")
        XCTAssertNotNil(dashIdx, "Last segment should contain a dash separating nano from filename")
        let nanoSegment = String(lastPart[lastPart.startIndex..<dashIdx!])
        XCTAssertEqual(nanoSegment.count, 10, "Nano ID segment should be 10 chars, got: '\(nanoSegment)'")
    }

    func testMakeObjectKeyContainsDateComponents() {
        let key = URLBuilder.makeObjectKey(for: "doc.pdf", prefix: "docs")
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        XCTAssertGreaterThanOrEqual(parts.count, 4)
        // parts[1] = year (4 digits), parts[2] = month (2 digits), parts[3] = day (2 digits)
        let year = String(parts[1])
        let month = String(parts[2])
        let day = String(parts[3])
        XCTAssertEqual(year.count, 4, "Year should be 4 digits, got: \(year)")
        XCTAssertEqual(month.count, 2, "Month should be 2 digits, got: \(month)")
        XCTAssertEqual(day.count, 2, "Day should be 2 digits, got: \(day)")
        XCTAssertNotNil(Int(year))
        XCTAssertNotNil(Int(month))
        XCTAssertNotNil(Int(day))
    }

    func testMakeObjectKeyPrefixWithTrailingSlashNotDoubled() {
        let key = URLBuilder.makeObjectKey(for: "file.txt", prefix: "uploads/")
        XCTAssertFalse(key.hasPrefix("uploads//"), "Trailing slash in prefix should not double, got: \(key)")
    }

    // MARK: - nanoId(length:)

    func testNanoIdLength() {
        let id = URLBuilder.nanoId(length: 10)
        XCTAssertEqual(id.count, 10)
    }

    func testNanoIdAlphabetOnly() {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let id = URLBuilder.nanoId(length: 20)
        XCTAssertTrue(id.unicodeScalars.allSatisfy { allowed.contains($0) },
                      "nanoId should only use alphanumeric chars, got: \(id)")
    }

    func testNanoIdDifferentEachCall() {
        // Very unlikely two 10-char IDs are the same
        let id1 = URLBuilder.nanoId(length: 10)
        let id2 = URLBuilder.nanoId(length: 10)
        // This might theoretically fail but probability is astronomically low
        XCTAssertNotEqual(id1, id2, "Two nanoIds should almost never be equal")
    }

    // MARK: - URLBuilder init / apiHost / apiBaseURL

    func testVirtualHostedStyle() {
        let builder = URLBuilder(
            region: "us-east-1",
            bucket: "my-bucket",
            endpointOverride: nil,
            forcePathStyle: false,
            cdnBaseURL: nil
        )
        XCTAssertEqual(builder.apiHost, "my-bucket.s3.us-east-1.amazonaws.com")
        XCTAssertEqual(builder.apiBaseURL().absoluteString, "https://my-bucket.s3.us-east-1.amazonaws.com")
    }

    func testPathStyle() {
        let builder = URLBuilder(
            region: "us-east-1",
            bucket: "my-bucket",
            endpointOverride: nil,
            forcePathStyle: true,
            cdnBaseURL: nil
        )
        XCTAssertEqual(builder.apiHost, "s3.us-east-1.amazonaws.com")
        XCTAssertEqual(builder.apiBaseURL().absoluteString, "https://s3.us-east-1.amazonaws.com/my-bucket")
    }

    func testDottedBucketAutoFallsBackToPathStyle() {
        let builder = URLBuilder(
            region: "eu-west-1",
            bucket: "files.weteling.com",
            endpointOverride: nil,
            forcePathStyle: false,
            cdnBaseURL: nil
        )
        XCTAssertEqual(builder.apiHost, "s3.eu-west-1.amazonaws.com")
        XCTAssertEqual(builder.apiBaseURL().absoluteString,
                       "https://s3.eu-west-1.amazonaws.com/files.weteling.com")
    }

    func testEndpointOverridePathStyle() {
        let builder = URLBuilder(
            region: "us-east-1",
            bucket: "my-bucket",
            endpointOverride: "https://s3.minio.local",
            forcePathStyle: true,
            cdnBaseURL: nil
        )
        XCTAssertEqual(builder.apiHost, "s3.minio.local")
    }

    func testEndpointOverrideBaseURL() {
        let builder = URLBuilder(
            region: "us-east-1",
            bucket: "my-bucket",
            endpointOverride: "https://s3.minio.local",
            forcePathStyle: true,
            cdnBaseURL: nil
        )
        // With forcePathStyle and override, base URL is https://s3.minio.local/my-bucket
        let base = builder.apiBaseURL().absoluteString
        XCTAssertTrue(base.hasPrefix("https://s3.minio.local"), "Base URL should use override host, got: \(base)")
    }

    // MARK: - objectURL

    func testObjectURLAppendsKey() {
        let builder = URLBuilder(
            region: "us-east-1",
            bucket: "my-bucket",
            endpointOverride: nil,
            forcePathStyle: false,
            cdnBaseURL: nil
        )
        let url = builder.objectURL(key: "foo/bar.txt")
        XCTAssertTrue(url.absoluteString.hasSuffix("/foo/bar.txt"),
                      "objectURL should end with /foo/bar.txt, got: \(url.absoluteString)")
        XCTAssertEqual(url.host, "my-bucket.s3.us-east-1.amazonaws.com")
    }

    func testObjectURLPathStyleAppendsKey() {
        let builder = URLBuilder(
            region: "us-east-1",
            bucket: "my-bucket",
            endpointOverride: nil,
            forcePathStyle: true,
            cdnBaseURL: nil
        )
        let url = builder.objectURL(key: "foo/bar.txt")
        XCTAssertTrue(url.absoluteString.contains("/my-bucket/foo/bar.txt"),
                      "Path-style objectURL should contain /my-bucket/foo/bar.txt, got: \(url.absoluteString)")
    }
}
