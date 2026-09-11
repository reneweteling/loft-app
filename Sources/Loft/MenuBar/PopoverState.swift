import SwiftUI

/// Popover UI state that outlives one show/hide cycle. The hosting controller
/// keeps the SwiftUI view tree alive between openings, so a plain `@State`
/// would remember the History tab forever. Anything the status item wants to
/// reset (a drag-enter needs the drop grid on screen) lives here instead.
@MainActor
final class PopoverState: ObservableObject {
    enum Tab: String, CaseIterable { case drop = "Drop", history = "History" }

    @Published var tab: Tab = .drop

    func showDropGrid() {
        tab = .drop
    }
}
