import UIKit
import Firebase
import UserNotifications
import FirebaseMessaging

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    let gcmMessageIDKey = "gcm.message_id"
    var window: UIWindow?

    // MARK: - Application Lifecycle
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Firebase 초기화
        FirebaseApp.configure()
        print("Firebase configured.")
        
        // UNUserNotificationCenter delegate 설정
        UNUserNotificationCenter.current().delegate = self
        
        // 알림 권한 요청
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("Permission granted: \(granted)")
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        
        // FCM 메시징 델리게이트 설정
        Messaging.messaging().delegate = self
        
        return true
    }

    // MARK: - Remote Notifications
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("Device Token: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")
        
        // APNS 토큰을 FCM에 전달
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        print("Foreground notification: \(userInfo)")
        completionHandler([[.banner, .badge, .sound]])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("Notification response: \(userInfo)")
        
        // 알림 클릭 시 URL 처리
        if let uri = userInfo["uri"] as? String {
            let fullURL: String
            if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
                fullURL = uri
            } else {
                fullURL = "https://togethery.store" + uri
            }
            
            DispatchQueue.main.async {
                let webViewController = WebViewController()
                webViewController.targetURL = fullURL
                if let rootViewController = self.window?.rootViewController {
                       let alert = UIAlertController(title: "알림 이동", message: "URI: \(fullURL)", preferredStyle: .alert)
                       alert.addAction(UIAlertAction(title: "확인", style: .default, handler: nil))
                       rootViewController.present(alert, animated: true, completion: nil)
                   }
                
                if let rootViewController = self.window?.rootViewController {
                    rootViewController.present(webViewController, animated: true, completion: nil)
                }
            }
        }
        
        completionHandler()
    }
    func applicationDidBecomeActive(_ application: UIApplication) {
        NotificationCenter.default.post(name: NSNotification.Name("AppDidBecomeActive"), object: nil)
    }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else {
            print("Failed to retrieve FCM registration token.")
            return
        }
    }
}
