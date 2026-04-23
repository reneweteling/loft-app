import Foundation
import AppKit

/// Zips a folder to a temp file using the system `/usr/bin/ditto` (handles symlinks, resource forks, large trees).
enum FolderZipper {
    static func zip(folder: URL) throws -> URL {
        let folderName = folder.lastPathComponent
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("loft-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let outURL = tmp.appendingPathComponent("\(folderName).zip")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent",
                             folder.path, outURL.path]

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errMsg = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "ditto failed"
            throw NSError(domain: "FolderZipper", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: errMsg])
        }

        return outURL
    }
}
