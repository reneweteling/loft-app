import XCTest
@testable import Loft

final class UploadURLTests: XCTestCase {
    func testRoundTripKeepsAwkwardPaths() {
        let paneID = UUID()
        let files = [
            URL(fileURLWithPath: "/Users/rene/Desktop/Screen Shot 2026-09-11.png"),
            URL(fileURLWithPath: "/tmp/één & twee 100%.mov"),
            URL(fileURLWithPath: "/Volumes/Data/folder+name/#hash?query.pdf")
        ]
        let url = UploadURL.build(paneID: paneID, files: files)
        let parsed = UploadURL.parse(url)
        XCTAssertEqual(parsed, UploadURL.Request(paneID: paneID, files: files))
    }

    func testHexMatchesShellEncoding() {
        // What `printf '%s' "$f" | od -An -v -tx1 | tr -d ' \n'` emits.
        XCTAssertEqual(UploadURL.encodeHex("/a b"), "2f612062")
        XCTAssertEqual(UploadURL.decodeHex("2f612062"), "/a b")
    }

    func testRejectsOtherSchemesHostsAndBrokenInput() {
        let id = UUID().uuidString
        XCTAssertNil(UploadURL.parse(URL(string: "https://upload?pane=\(id)&f=2f61")!))
        XCTAssertNil(UploadURL.parse(URL(string: "loft://settings?pane=\(id)&f=2f61")!))
        XCTAssertNil(UploadURL.parse(URL(string: "loft://upload?pane=not-a-uuid&f=2f61")!))
        XCTAssertNil(UploadURL.parse(URL(string: "loft://upload?pane=\(id)")!))
        XCTAssertNil(UploadURL.parse(URL(string: "loft://upload?pane=\(id)&f=zz")!))
        XCTAssertNil(UploadURL.parse(URL(string: "loft://upload?pane=\(id)&f=2f6")!))
    }

    func testSkipsUndecodableEntriesButKeepsTheRest() {
        let id = UUID()
        let url = URL(string: "loft://upload?pane=\(id.uuidString)&f=zz&f=2f61")!
        XCTAssertEqual(UploadURL.parse(url)?.files, [URL(fileURLWithPath: "/a")])
    }
}
