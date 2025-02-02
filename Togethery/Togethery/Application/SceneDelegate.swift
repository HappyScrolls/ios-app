import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // WebViewController를 기본 뷰로 설정
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = WebViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
}
