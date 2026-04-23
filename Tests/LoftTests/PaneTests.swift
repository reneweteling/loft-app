import XCTest
@testable import Loft

final class PaneTests: XCTestCase {

    // MARK: - TTL.tagValue

    func testTTLNoneTagValue() {
        XCTAssertEqual(TTL.none.tagValue, "none")
    }

    func testTTLOneDayTagValue() {
        XCTAssertEqual(TTL.days(1).tagValue, "1d")
    }

    func testTTLThirtyDaysTagValue() {
        XCTAssertEqual(TTL.days(30).tagValue, "30d")
    }

    // MARK: - TTL.humanLabel

    func testTTLOneDayHumanLabel() {
        XCTAssertEqual(TTL.days(1).humanLabel, "1 day")
    }

    func testTTLThirtyDaysHumanLabel() {
        XCTAssertEqual(TTL.days(30).humanLabel, "30 days")
    }

    func testTTLNoneHumanLabel() {
        XCTAssertEqual(TTL.none.humanLabel, "No expiry")
    }

    // MARK: - Pane.defaults

    func testPaneDefaultsCount() {
        XCTAssertEqual(Pane.defaults.count, 4)
    }

    func testPaneDefaultsOrder() {
        let names = Pane.defaults.map { $0.name }
        XCTAssertEqual(names, ["Private", "1 Day", "30 Days", "Public"])
    }

    func testPaneDefaultsFirstIsPrivate() {
        let first = Pane.defaults[0]
        XCTAssertEqual(first.name, "Private")
        XCTAssertEqual(first.visibility, .private)
        XCTAssertEqual(first.ttl, .none)
    }

    func testPaneDefaultsOneDayPane() {
        let pane = Pane.defaults[1]
        XCTAssertEqual(pane.name, "1 Day")
        XCTAssertEqual(pane.visibility, .public)
        XCTAssertEqual(pane.ttl, .days(1))
    }

    func testPaneDefaultsThirtyDaysPane() {
        let pane = Pane.defaults[2]
        XCTAssertEqual(pane.name, "30 Days")
        XCTAssertEqual(pane.visibility, .public)
        XCTAssertEqual(pane.ttl, .days(30))
    }

    func testPaneDefaultsPublicPane() {
        let pane = Pane.defaults[3]
        XCTAssertEqual(pane.name, "Public")
        XCTAssertEqual(pane.visibility, .public)
        XCTAssertEqual(pane.ttl, .none)
    }

    // MARK: - JSON round-trip

    func testPaneDefaultsJSONRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(Pane.defaults)
        let decoded = try decoder.decode([Pane].self, from: data)
        XCTAssertEqual(decoded.count, Pane.defaults.count)
        for (original, roundTripped) in zip(Pane.defaults, decoded) {
            XCTAssertEqual(original.name, roundTripped.name)
            XCTAssertEqual(original.ttl, roundTripped.ttl)
            XCTAssertEqual(original.visibility, roundTripped.visibility)
            XCTAssertEqual(original.keyPrefix, roundTripped.keyPrefix)
            XCTAssertEqual(original.tintHex, roundTripped.tintHex)
            XCTAssertEqual(original.iconSystemName, roundTripped.iconSystemName)
            XCTAssertEqual(original.order, roundTripped.order)
            XCTAssertEqual(original.enabled, roundTripped.enabled)
            // UUIDs are regenerated since `id` has a default of UUID()
            // They are encoded/decoded from JSON so they should match
            XCTAssertEqual(original.id, roundTripped.id)
        }
    }
}
