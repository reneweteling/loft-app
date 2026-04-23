import XCTest
@testable import Loft

final class UpdateCheckerTests: XCTestCase {
    func testSemverEqual() {
        XCTAssertEqual(compareSemver("1.2.3", "1.2.3"), .orderedSame)
    }

    func testSemverPatchHigher() {
        XCTAssertEqual(compareSemver("1.2.4", "1.2.3"), .orderedDescending)
    }

    func testSemverMinorHigher() {
        XCTAssertEqual(compareSemver("1.3.0", "1.2.9"), .orderedDescending)
    }

    func testSemverMajorHigher() {
        XCTAssertEqual(compareSemver("2.0.0", "1.99.99"), .orderedDescending)
    }

    func testSemverDoubleDigitPatch() {
        XCTAssertEqual(compareSemver("1.2.10", "1.2.9"), .orderedDescending)
    }

    func testSemverStripsLeadingV() {
        XCTAssertEqual(compareSemver("v1.2.3", "1.2.3"), .orderedSame)
    }

    func testSemverMissingComponents() {
        XCTAssertEqual(compareSemver("1.2", "1.2.0"), .orderedSame)
    }
}
