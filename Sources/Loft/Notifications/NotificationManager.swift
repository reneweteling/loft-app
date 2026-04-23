import Foundation
import UserNotifications
import AppKit

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private var urlsByRequestId: [String: URL] = [:]

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await requestAuthorization() }
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func notifySuccess(url: URL, fileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Upload complete"
        content.body = "\(fileName)\n\(url.absoluteString)"
        if AppConfig.shared.notificationSound { content.sound = .default }
        content.userInfo = ["url": url.absoluteString]

        let id = UUID().uuidString
        urlsByRequestId[id] = url
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if error != nil {
                // Fallback: copy URL immediately if notifications denied
                Task { @MainActor in
                    self?.copyToClipboard(url: url)
                }
            }
        }
    }

    func notifyFailure(fileName: String, message: String) {
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
        showCopyConfirmation()
    }

    private func showCopyConfirmation() {
        let content = UNMutableNotificationContent()
        content.title = "Copied to clipboard"
        content.body = "URL ready to paste."
        if AppConfig.shared.notificationSound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let s = info["url"] as? String, let url = URL(string: s) else { return }
        await MainActor.run { self.copyToClipboard(url: url) }
    }
}
