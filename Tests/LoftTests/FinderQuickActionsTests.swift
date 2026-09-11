import XCTest
@testable import Loft

final class FinderQuickActionsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("loft-qa-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func pane(_ name: String, order: Int, enabled: Bool = true) -> Pane {
        Pane(name: name, iconSystemName: "globe", tintHex: "#000000", ttl: .none,
             visibility: .public, keyPrefix: "x/", order: order, enabled: enabled)
    }

    private func bundles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    func testWritesOneBundlePerEnabledPane() throws {
        let panes = [pane("Private", order: 0), pane("1 Day", order: 1), pane("Off", order: 2, enabled: false)]
        XCTAssertTrue(FinderQuickActions.sync(panes: panes, directory: directory, notifySystem: false))
        XCTAssertEqual(bundles(), ["Upload to Loft (1 Day).workflow", "Upload to Loft (Private).workflow"])

        let info = directory.appendingPathComponent("Upload to Loft (Private).workflow/Contents/Info.plist")
        let dict = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: try Data(contentsOf: info), format: nil) as? [String: Any])
        XCTAssertEqual(dict[FinderQuickActions.paneIDKey] as? String, panes[0].id.uuidString)
        let services = try XCTUnwrap(dict["NSServices"] as? [[String: Any]])
        XCTAssertEqual((services.first?["NSMenuItem"] as? [String: String])?["default"], "Upload to Loft (Private)")
        XCTAssertEqual(services.first?["NSMessage"] as? String, "runWorkflowAsService")
    }

    func testScriptTargetsThePaneThroughTheURLScheme() throws {
        let p = pane("Public", order: 3)
        FinderQuickActions.sync(panes: [p], directory: directory, notifySystem: false)
        let wflow = directory.appendingPathComponent("Upload to Loft (Public).workflow/Contents/document.wflow")
        let text = try String(contentsOf: wflow, encoding: .utf8)
        XCTAssertTrue(text.contains("loft://upload?pane=\(p.id.uuidString)"))
        XCTAssertTrue(text.contains("od -An -v -tx1"))
        XCTAssertTrue(text.contains("<string>/bin/zsh</string>"))
    }

    func testSecondSyncIsANoOpAndRenameMovesTheBundle() {
        var p = pane("Private", order: 0)
        FinderQuickActions.sync(panes: [p], directory: directory, notifySystem: false)
        XCTAssertFalse(FinderQuickActions.sync(panes: [p], directory: directory, notifySystem: false))

        p.name = "Team"
        XCTAssertTrue(FinderQuickActions.sync(panes: [p], directory: directory, notifySystem: false))
        XCTAssertEqual(bundles(), ["Upload to Loft (Team).workflow"])
    }

    func testRemovesBundlesForDroppedPanesAndLeavesForeignOnesAlone() throws {
        let foreign = directory.appendingPathComponent("Mine.workflow/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        try "<plist version=\"1.0\"><dict/></plist>".write(
            to: foreign.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let a = pane("A", order: 0), b = pane("B", order: 1)
        FinderQuickActions.sync(panes: [a, b], directory: directory, notifySystem: false)
        FinderQuickActions.sync(panes: [a], directory: directory, notifySystem: false)
        XCTAssertEqual(bundles(), ["Mine.workflow", "Upload to Loft (A).workflow"])

        FinderQuickActions.sync(panes: [], directory: directory, notifySystem: false)
        XCTAssertEqual(bundles(), ["Mine.workflow"])
    }

    func testDuplicateAndUnsafeNamesGetDistinctFileNames() {
        let panes = [pane("Temp", order: 0), pane("Temp", order: 1), pane("a/b:c", order: 2)]
        FinderQuickActions.sync(panes: panes, directory: directory, notifySystem: false)
        XCTAssertEqual(bundles(), [
            "Upload to Loft (Temp) 2.workflow",
            "Upload to Loft (Temp).workflow",
            "Upload to Loft (a-b-c).workflow"
        ])
    }
}
