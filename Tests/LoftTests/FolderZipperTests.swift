import XCTest
import ZIPFoundation
@testable import Loft

final class FolderZipperTests: XCTestCase {
    func testZipKeepsFolderNameAndNestedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("loft-zip-test-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Photos 2026", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        try "top".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try Data(repeating: 0x41, count: 200_000)
            .write(to: folder.appendingPathComponent("sub/b.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let zip = try FolderZipper.zip(folder: folder)
        defer { try? FileManager.default.removeItem(at: zip.deletingLastPathComponent()) }
        XCTAssertEqual(zip.lastPathComponent, "Photos 2026.zip")

        let archive = try Archive(url: zip, accessMode: .read)
        let paths = Set(archive.map(\.path))
        XCTAssertTrue(paths.contains("Photos 2026/a.txt"), "\(paths)")
        XCTAssertTrue(paths.contains("Photos 2026/sub/b.bin"), "\(paths)")

        let big = try XCTUnwrap(archive["Photos 2026/sub/b.bin"])
        XCTAssertEqual(big.uncompressedSize, 200_000)
        XCTAssertLessThan(big.compressedSize, 10_000, "deflate should crush a run of identical bytes")
    }
}
