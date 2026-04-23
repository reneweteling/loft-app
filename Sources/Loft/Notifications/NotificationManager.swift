import Foundation
import UserNotifications
import AppKit

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private var hasRequestedAuthorization = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Request notification permission only when the user explicitly opts in
    /// via Settings → General. Idempotent — prompts once per process at most.
    func requestAuthorizationIfOptedIn() async {
        guard AppConfig.shared.showSystemNotifications, !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func notifySuccess(url: URL, fileName: String) {
        copyToClipboard(url: url)
        guard AppConfig.shared.showSystemNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upload complete — URL copied"
        content.body = "\(fileName)\n\(url.absoluteString)"
        if AppConfig.shared.notificationSound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func notifyFailure(fileName: String, message: String) {
        guard AppConfig.shared.showSystemNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "Upload failed"
        content.body = "\(fileName): \(message)"
        if AppConfig.shared.notificationSound { content.sound = .defaultCritical }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func copyToClipboard(url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
