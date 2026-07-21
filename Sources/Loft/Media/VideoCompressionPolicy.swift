import Foundation

/// What Loft does when a video crosses the size threshold on drop.
enum VideoCompressionPolicy: String, CaseIterable, Identifiable {
    case ask
    case always
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ask: return "Ask each time"
        case .always: return "Always compress"
        case .never: return "Never compress"
        }
    }
}

/// Where a dropped file goes: straight to S3, through the encoder first, or to
/// a prompt in the popover. Pure so it can be tested without UserDefaults.
enum CompressionRoute: Equatable {
    case asIs
    case compress
    case ask

    static func decide(isVideo: Bool,
                       fileSize: Int64,
                       thresholdMB: Int,
                       policy: VideoCompressionPolicy) -> CompressionRoute {
        guard isVideo else { return .asIs }
        let threshold = Int64(max(0, thresholdMB)) * 1_048_576
        guard fileSize > threshold else { return .asIs }
        switch policy {
        case .ask: return .ask
        case .always: return .compress
        case .never: return .asIs
        }
    }
}
