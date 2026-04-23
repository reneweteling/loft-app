import XCTest
@testable import Loft

final class SigV4SignerTests: XCTestCase {

    // MARK: - hexSHA256

    func testHexSHA256EmptyString() {
        // SHA-256 of empty string is the well-known constant
        let result = SigV4Signer.hexSHA256("")
        XCTAssertEqual(
            result,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testHexSHA256KnownValue() {
        // SHA-256("abc")
        let result = SigV4Signer.hexSHA256("abc")
        XCTAssertEqual(
            result,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    // MARK: - rfc3986Encode

    func testRfc3986EncodeSpace() {
        XCTAssertEqual(SigV4Signer.rfc3986Encode("hello world"), "hello%20world")
    }

    func testRfc3986EncodeSlashAndPlus() {
        XCTAssertEqual(SigV4Signer.rfc3986Encode("a/b+c"), "a%2Fb%2Bc")
    }

    func testRfc3986EncodeUnreservedCharacters() {
        // Unreserved characters must not be encoded
        XCTAssertEqual(SigV4Signer.rfc3986Encode("~-._"), "~-._")
    }

    func testRfc3986EncodeAlphanumeric() {
        XCTAssertEqual(SigV4Signer.rfc3986Encode("abc123"), "abc123")
    }

    // MARK: - canonicalQueryString

    func testCanonicalQueryStringSortsByNameThenValue() {
        // Items: (b,1), (a,2), (a,1) → sorted: a=1&a=2&b=1
        let items = [
            URLQueryItem(name: "b", value: "1"),
            URLQueryItem(name: "a", value: "2"),
            URLQueryItem(name: "a", value: "1")
        ]
        let result = SigV4Signer.canonicalQueryString(from: items)
        XCTAssertEqual(result, "a=1&a=2&b=1")
    }

    func testCanonicalQueryStringEncodesBothNameAndValue() {
        let items = [URLQueryItem(name: "my key", value: "my value")]
        let result = SigV4Signer.canonicalQueryString(from: items)
        XCTAssertEqual(result, "my%20key=my%20value")
    }

    func testCanonicalQueryStringEmpty() {
        XCTAssertEqual(SigV4Signer.canonicalQueryString(from: []), "")
    }

    // MARK: - presignGet structural checks

    func testPresignGetContainsRequiredQueryParams() throws {
        let creds = SigV4Credentials(
            accessKeyId: "AKIDEXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
        )
        let inputURL = URL(string: "https://my-bucket.s3.us-east-1.amazonaws.com/test-key")!
        let result = try SigV4Signer.presignGet(
            url: inputURL,
            region: "us-east-1",
            credentials: creds,
            expiresIn: 3600
        )

        let urlString = result.absoluteString
        XCTAssertTrue(urlString.contains("X-Amz-Algorithm=AWS4-HMAC-SHA256"),
                      "URL should contain X-Amz-Algorithm=AWS4-HMAC-SHA256, got: \(urlString)")
        XCTAssertTrue(urlString.contains("X-Amz-Signature="),
                      "URL should contain X-Amz-Signature=, got: \(urlString)")
        XCTAssertTrue(urlString.contains("X-Amz-Expires=3600"),
                      "URL should contain X-Amz-Expires=3600, got: \(urlString)")
        XCTAssertTrue(urlString.contains("X-Amz-Credential=AKIDEXAMPLE"),
                      "URL should contain X-Amz-Credential=AKIDEXAMPLE, got: \(urlString)")
        XCTAssertTrue(urlString.contains("X-Amz-SignedHeaders=host"),
                      "URL should contain X-Amz-SignedHeaders=host, got: \(urlString)")
    }

    func testPresignGetSchemeAndHostPreserved() throws {
        let creds = SigV4Credentials(
            accessKeyId: "AKIDEXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
        )
        let inputURL = URL(string: "https://my-bucket.s3.us-east-1.amazonaws.com/some/path")!
        let result = try SigV4Signer.presignGet(
            url: inputURL,
            region: "us-east-1",
            credentials: creds,
            expiresIn: 3600
        )
        XCTAssertEqual(result.scheme, "https")
        XCTAssertEqual(result.host, "my-bucket.s3.us-east-1.amazonaws.com")
        XCTAssertEqual(result.path, "/some/path")
    }

    func testPresignGetSignatureIsHexString() throws {
        let creds = SigV4Credentials(
            accessKeyId: "AKIDEXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
        )
        let inputURL = URL(string: "https://my-bucket.s3.us-east-1.amazonaws.com/key")!
        let result = try SigV4Signer.presignGet(
            url: inputURL,
            region: "us-east-1",
            credentials: creds,
            expiresIn: 3600
        )
        let comps = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let sig = comps.queryItems?.first(where: { $0.name == "X-Amz-Signature" })?.value
        XCTAssertNotNil(sig)
        // A SHA256 HMAC hex is 64 hex chars
        XCTAssertEqual(sig?.count, 64)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(sig!.unicodeScalars.allSatisfy { hexChars.contains($0) },
                      "Signature should be lowercase hex, got: \(sig!)")
    }
}
