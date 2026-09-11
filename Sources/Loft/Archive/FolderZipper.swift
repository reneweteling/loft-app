import Foundation
import ZIPFoundation

/// Zips a folder to a temp file, in-process. No `ditto` child process: inside
/// the App Sandbox a helper would not be guaranteed the access a drop grants
/// on the folder, and the store build has to behave exactly like the GitHub
/// build. Entries are deflated and keep the folder as their top-level name,
/// so unzipping gives the folder back rather than its loose contents.
enum FolderZipper {
    static func zip(folder: URL) throws -> URL {
        let folderName = folder.lastPathComponent
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("loft-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let outURL = tmp.appendingPathComponent("\(folderName).zip")
        try FileManager.default.zipItem(at: folder, to: outURL,
                                        shouldKeepParent: true,
                                        compressionMethod: .deflate)
        return outURL
    }
}
