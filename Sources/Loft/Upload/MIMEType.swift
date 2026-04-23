import Foundation
import UniformTypeIdentifiers

enum MIMEType {
    static func forFile(name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        guard !ext.isEmpty,
              let ut = UTType(filenameExtension: ext),
              let mime = ut.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mime
    }
}
