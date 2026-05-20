import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging
import GoogleMobileAds

@main
struct LiveLensApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            HomeView()
                .onOpenURL { url in
                    NotificationCenter.default.post(name: .incomingAnalysisURL, object: url)
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        Auth.auth().signInAnonymously { _, _ in }

        #if DEBUG
        HistoryStore.shared.loadDummyEntries()

        let settings = FirestoreSettings()
        settings.host = "127.0.0.1:8080"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
        Functions.functions(region: "us-central1").useEmulator(withHost: "127.0.0.1", port: 5001)
        #endif

        GADMobileAds.sharedInstance().start { _ in
            Task { await RewardedAdService.shared.load() }
        }
        FCMService.shared.setup()
        Task { await FCMService.shared.requestPermission() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}
