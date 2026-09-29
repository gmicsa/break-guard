import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() {}

    weak var sessionManager: SessionManager?

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Snooze \(SettingsManager.shared.snoozeDurationMinutes) min",
            options: []
        )
        let warnCategory = UNNotificationCategory(
            identifier: "BREAK_WARN",
            actions: [snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        let infoCategory = UNNotificationCategory(
            identifier: "BREAK_INFO",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([warnCategory, infoCategory])

        center.requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.updatePermissionWarning(granted: granted) }
        }
    }

    func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let denied = settings.authorizationStatus == .denied
                AppDelegate.shared?.setNotificationWarningVisible(denied)
            }
        }
    }

    private func updatePermissionWarning(granted: Bool) {
        AppDelegate.shared?.setNotificationWarningVisible(!granted)
    }

    func sendInfoNotification(elapsedMinutes: Int) {
        send(id: "break_info",
             title: "Time for a break! 🌿",
             body: "You've been working for \(elapsedMinutes) minutes. Step away and rest.",
             categoryId: "BREAK_INFO")
        SoundManager.shared.playInfo()
    }

    func sendWarningNotification(elapsedMinutes: Int) {
        send(id: "break_warn_\(Int(Date().timeIntervalSince1970))",
             title: "Still working? 🔴",
             body: "You've been at it for \(elapsedMinutes) minutes. Your body needs a break.",
             categoryId: "BREAK_WARN")
        SoundManager.shared.playWarning()
    }

    func sendSnoozeEndNotification() {
        send(id: "snooze_end",
             title: "Snooze over 🔔",
             body: "Break reminder is back. Consider stepping away now.",
             categoryId: "BREAK_WARN")
        SoundManager.shared.playWarning()
    }

    private func send(id: String, title: String, body: String, categoryId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryId
        content.sound = .none
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "SNOOZE" {
            DispatchQueue.main.async { self.sessionManager?.snooze() }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
