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
        button.image = Self.menuBarImage(active: false)
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
        button.image = Self.menuBarImage(active: active)
    }

    /// The blue app icon rendered for the menu bar. Full colour (not a template),
    /// with a small accent dot in the corner while an upload is in flight so the
    /// status item keeps the ambient "busy" signal the SF Symbol fill gave.
    private static func menuBarImage(active: Bool) -> NSImage {
        let side = max(NSStatusBar.system.thickness - 2, 20)
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(side * scale), pixelsHigh: Int(side * scale),
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
        ) else {
            return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        }
        rep.size = NSSize(width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        appIcon.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                     from: .zero, operation: .sourceOver, fraction: 1.0)

        if active {
            let d = side * 0.38
            let dot = NSBezierPath(ovalIn: NSRect(x: side - d, y: 0, width: d, height: d)
                .insetBy(dx: side * 0.03, dy: side * 0.03))
            NSColor.controlAccentColor.setFill()
            NSColor.white.setStroke()
            dot.lineWidth = side * 0.07
            dot.fill()
            dot.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
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
