import UIKit
@preconcurrency import WebKit
import Firebase
import UserNotifications
import FirebaseMessaging
import JWTDecode

class WebViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    // MARK: - Components
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true // JavaScript 활성화
        configuration.websiteDataStore = .default() // 캐싱 활성화
        configuration.userContentController.add(self, name: "nativeHandler") // JavaScript 브리지
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }()
    
    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .gray
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    private lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshWebView), for: .valueChanged)
        return refreshControl
    }()
    
    // 특정 URL로 이동하기 위한 변수
    var targetURL: String?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupUI()
        loadWebPage()
    }

    // MARK: - Setup UI
    private func setupUI() {
        view.addSubview(webView)
        view.addSubview(activityIndicator)
        webView.scrollView.addSubview(refreshControl) // Pull-to-Refresh 추가
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), // Safe Area 적용
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        webView.scrollView.isScrollEnabled = false // 스크롤 동작 막기
        webView.scrollView.bounces = false// 스크롤 끝에서 튕김 효과 제거
    }
    
    // MARK: - Setup Navigation Bar
    private func setupNavigationBar() {
        let backButton = UIBarButtonItem(title: "뒤로", style: .plain, target: self, action: #selector(goBack))
        navigationItem.leftBarButtonItem = backButton
    }

    // MARK: - Load Web Page
    private func loadWebPage() {
        let uri = targetURL ?? ""
        let urlString = "https://togethery.store/" + uri
        guard let url = URL(string: urlString) else {
            showErrorAlert(message: "유효하지 않은 URL입니다.")
            return
        }
        let request = URLRequest(url: url)
        webView.load(request)
    }

    // MARK: - Refresh WebView
    @objc private func refreshWebView() {
        webView.reload()
        refreshControl.endRefreshing()
    }

    // MARK: - Navigation Actions
    @objc private func goBack() {
        if webView.canGoBack {
            webView.goBack()
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activityIndicator.startAnimating()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        showErrorAlert(message: "페이지를 로드할 수 없습니다. 네트워크 상태를 확인해주세요.")
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            if url.absoluteString.contains("redirect") {
                print("redirect!!!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.fetchAuthTokenAndSendFCMToken()
                }
            }
        }
        decisionHandler(.allow)
    }

    // MARK: - Fetch Auth Token and Send FCM Token
    private func fetchAuthTokenAndSendFCMToken() {
        let script = "localStorage.getItem('authToken');"
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error = error {
                print("Error fetching authToken: \(error.localizedDescription)")
                return
            }
            guard let authToken = result as? String else {
                print("authToken not found or invalid.")
                return
            }
            print("Auth Token: \(authToken)")
            Messaging.messaging().token { fcmToken, error in
                if let error = error {
                    print("Error fetching FCM token: \(error.localizedDescription)")
                    return
                }
                guard let fcmToken = fcmToken else {
                    print("FCM token is nil.")
                    return
                }
                print("FCM Token: \(fcmToken)")
                if let memberCode = self?.decodeAuthToken(authToken: authToken) {
                    print("Member Code: \(memberCode)")
                    self?.sendFCMTokenToServer(memberCode: memberCode, fcmToken: fcmToken)
                } else {
                    print("Failed to decode authToken.")
                }
            }
        }
    }

    private func decodeAuthToken(authToken: String) -> String? {
        do {
            let jwt = try decode(jwt: authToken)
            return jwt["Member-Code"].string
        } catch {
            print("Failed to decode authToken: \(error.localizedDescription)")
            return nil
        }
    }

    private func sendFCMTokenToServer(memberCode: String, fcmToken: String) {
        guard let url = URL(string: "https://api.togethery.store/notification/fcm-key") else {
            print("Invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(memberCode, forHTTPHeaderField: "Member-Code")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["key": fcmToken], options: [])
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error sending FCM token to server: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print("Server response status code: \(httpResponse.statusCode)")
            }
        }.resume()
    }

    // MARK: - JavaScript Bridge
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "nativeHandler", let messageBody = message.body as? String {
            print("Received message from web: \(messageBody)")
        }
    }
    
    // MARK: - Error Handling
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "오류 발생", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
