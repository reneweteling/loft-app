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

/// How hard the H.265 encoder squeezes. Expressed as bits per pixel per frame,
/// the knob that actually drives HEVC file size at a fixed resolution.
enum VideoCompressionQuality: String, CaseIterable, Identifiable {
    case high
    case balanced
    case small

    var id: String { rawValue }

    /// Target bits-per-pixel-per-frame. For 1080p30 these land around 7.5 / 5 /
    /// 3 Mbps, all a large drop from the 20 Mbps+ screen recordings produce.
    var bitsPerPixel: Double {
        switch self {
        case .high: return 0.12
        case .balanced: return 0.08
        case .small: return 0.05
        }
    }

    var label: String {
        switch self {
        case .high: return "High quality"
        case .balanced: return "Balanced"
        case .small: return "Smallest file"
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
