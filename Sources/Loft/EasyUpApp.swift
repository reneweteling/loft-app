import SwiftUI
import AppKit

@main
struct LoftApp: App {
    @StateObject private var config = AppConfig.shared
    @StateObject private var uploadQueue = UploadQueue.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Loft Settings", id: "settings") {
            SettingsView()
                .environmentObject(config)
                .frame(width: 560, height: 420)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        let config = AppConfig.shared
        let queue = UploadQueue.shared
        let popoverContent = PopoverView()
            .environmentObject(config)
            .environmentObject(queue)
        statusController = StatusItemController(rootView: popoverContent, uploadQueue: queue)
        Task { await UpdateChecker.shared.checkIfNeeded() }
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              window.identifier?.rawValue.contains("settings") == true || window.title == "Loft Settings" else {
            return
        }
        DispatchQueue.main.async {
            let stillOpen = NSApp.windows.contains { w in
                w != window && w.isVisible && !w.className.contains("StatusBar") && !w.className.contains("NSPopover")
            }
            if !stillOpen {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
