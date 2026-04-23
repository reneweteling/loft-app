import Foundation

enum TTL: Codable, Equatable, Hashable {
    case none
    case days(Int)

    var tagValue: String {
        switch self {
        case .none: return "none"
        case .days(let d): return "\(d)d"
        }
    }

    var humanLabel: String {
        switch self {
        case .none: return "No expiry"
        case .days(1): return "1 day"
        case .days(let d): return "\(d) days"
        }
    }
}

enum Visibility: String, Codable, Equatable {
    case `private`
    case `public`
}

struct Pane: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var iconSystemName: String
    var tintHex: String
    var ttl: TTL
    var visibility: Visibility
    var bucket: String?
    var keyPrefix: String
    var order: Int
    var enabled: Bool = true

    static let defaults: [Pane] = [
        Pane(name: "Private",
             iconSystemName: "lock.fill",
             tintHex: "#1F2937",
             ttl: .none,
             visibility: .private,
             keyPrefix: "private/",
             order: 0),
        Pane(name: "1 Day",
             iconSystemName: "calendar",
             tintHex: "#3B82F6",
             ttl: .days(1),
             visibility: .public,
             keyPrefix: "tmp1d/",
             order: 1),
        Pane(name: "30 Days",
             iconSystemName: "calendar.badge.clock",
             tintHex: "#A855F7",
             ttl: .days(30),
             visibility: .public,
             keyPrefix: "tmp30d/",
             order: 2),
        Pane(name: "Public",
             iconSystemName: "globe",
             tintHex: "#10B981",
             ttl: .none,
             visibility: .public,
             keyPrefix: "pub/",
             order: 3)
    ]
}
