import XCTest
@testable import Loft

final class CompressionRouteTests: XCTestCase {
    private let big: Int64 = 42 * 1_048_576
    private let small: Int64 = 3 * 1_048_576

    func testNonVideoAlwaysUploadsAsIs() {
        XCTAssertEqual(CompressionRoute.decide(isVideo: false, fileSize: big, thresholdMB: 10, policy: .always),
                       .asIs)
    }

    func testVideoUnderThresholdUploadsAsIs() {
        XCTAssertEqual(CompressionRoute.decide(isVideo: true, fileSize: small, thresholdMB: 10, policy: .ask),
                       .asIs)
    }

    func testThresholdIsExclusive() {
        XCTAssertEqual(CompressionRoute.decide(isVideo: true, fileSize: 10 * 1_048_576, thresholdMB: 10, policy: .ask),
                       .asIs)
        XCTAssertEqual(CompressionRoute.decide(isVideo: true, fileSize: 10 * 1_048_576 + 1, thresholdMB: 10, policy: .ask),
                       .ask)
    }

    func testPolicyDrivesLargeVideos() {
        XCTAssertEqual(CompressionRoute.decide(isVideo: true, fileSize: big, thresholdMB: 10, policy: .ask),
                       .ask)
        XCTAssertEqual(CompressionRoute.decide(isVideo: true, fileSize: big, thresholdMB: 10, policy: .always),
                       .compress)
        XCTAssertEqual(CompressionRoute.decide(isVideo: true, fileSize: big, thresholdMB: 10, policy: .never),
                       .asIs)
    }

    func testZeroThresholdCatchesEveryVideo() {
        XCTAssertEqual(CompressionRoute.decide(isVideo: true, fileSize: 1, thresholdMB: 0, policy: .always),
                       .compress)
    }

    func testVideoDetectionByExtension() {
        XCTAssertTrue(VideoCompressor.isVideo(URL(fileURLWithPath: "/tmp/clip.mp4")))
        XCTAssertTrue(VideoCompressor.isVideo(URL(fileURLWithPath: "/tmp/Screen Recording.MOV")))
        XCTAssertFalse(VideoCompressor.isVideo(URL(fileURLWithPath: "/tmp/shot.png")))
        XCTAssertFalse(VideoCompressor.isVideo(URL(fileURLWithPath: "/tmp/notes.txt")))
        XCTAssertFalse(VideoCompressor.isVideo(URL(fileURLWithPath: "/tmp/archive")))
    }
}
