import Foundation
import FirebaseMessaging
import UserNotifications

final class FCMService: NSObject, ObservableObject, MessagingDelegate, UNUserNotificationCenterDelegate {
    static let shared = FCMService()

    @Published var fcmToken: String? = UserDefaults.standard.string(forKey: "fcmToken")

    private override init() {
        super.init()
    }

    func setup() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        self.fcmToken = fcmToken
        UserDefaults.standard.set(fcmToken, forKey: "fcmToken")
        #if DEBUG
        print("FCM token:", fcmToken ?? "nil")
        #endif
    }

    // MARK: - UNUserNotificationCenterDelegate（フォアグラウンドでも通知を表示）

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
