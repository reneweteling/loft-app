import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let uploadQueue: UploadQueue
    private var cancellables: Set<AnyCancellable> = []
    private var dragTimer: Timer?

    @MainActor
    init<Content: View>(rootView: Content, uploadQueue: UploadQueue) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()
        self.uploadQueue = uploadQueue
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        configureButton()
        startActivityObserver()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: "Loft")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(togglePopover)

        let overlay = DragOverlayView(frame: button.bounds) { [weak self] in
            self?.handleDragEnter()
        }
        overlay.autoresizingMask = [.width, .height]
        button.addSubview(overlay)
    }

    @MainActor
    private func startActivityObserver() {
        uploadQueue.$items
            .map { items in items.contains { !$0.state.isTerminal } }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in self?.updateIcon(active: active) }
            .store(in: &cancellables)

        // A compress prompt needs an answer, so make sure it is on screen even if
        // the post-drag auto-close timer already fired.
        uploadQueue.$pendingCompressions
            .map { !$0.isEmpty }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] waiting in
                guard let self, waiting else { return }
                self.dragTimer?.invalidate()
                if !self.popover.isShown { self.showPopover() }
            }
            .store(in: &cancellables)
    }

    private func updateIcon(active: Bool) {
        guard let button = statusItem.button else { return }
        let name = active ? "arrow.up.circle.fill" : "arrow.up.circle"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Loft")
        button.image?.isTemplate = true
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func handleDragEnter() {
        if !popover.isShown { showPopover() }
        dragTimer?.invalidate()
        dragTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard self.uploadQueue.pendingCompressions.isEmpty else { return }
                if self.popover.isShown { self.popover.performClose(nil) }
            }
        }
    }
}

private final class DragOverlayView: NSView {
    private let onDragEnter: () -> Void

    init(frame: NSRect, onDragEnter: @escaping () -> Void) {
        self.onDragEnter = onDragEnter
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEnter()
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEnter()
        return []
    }
}
