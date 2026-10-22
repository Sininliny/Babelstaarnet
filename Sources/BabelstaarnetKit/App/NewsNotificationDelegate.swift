import Foundation
import UserNotifications

@MainActor final class NewsNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (@MainActor () -> Void)?
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        let relevant = response.notification.request.identifier == "Babelstaarnet.news.digest"
        Task { @MainActor [weak self] in if relevant { self?.onOpen?() } }
        completionHandler()
    }
}
