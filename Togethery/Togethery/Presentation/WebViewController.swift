import UIKit
@preconcurrency import WebKit
import Firebase
import UserNotifications
import FirebaseMessaging
import JWTDecode
import SnapKit

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
 
        webView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }
        
        activityIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        // 스크롤 설정
        webView.scrollView.isScrollEnabled = true // 스크롤 활성화
        webView.scrollView.bounces = false // 스크롤 끝에서 튕김 효과 제거
    }
    
    // MARK: - Setup Navigation Bar
    private func setupNavigationBar() {
        let backButton = UIBarButtonItem(title: "뒤로", style: .plain, target: self, action: #selector(goBack))
        navigationItem.leftBarButtonItem = backButton
    }
    
    private func loadWebPage() {
        guard let baseURL = URL(string: "https://togethery.store/") else {
            return
        }

        let memberCode = UserDefaults.standard.string(forKey: "Member-Code")
        let uri: String

        // Member-Code가 있는 경우
        if let memberCode = memberCode {
            if let targetURL = targetURL, !targetURL.isEmpty {
                uri = targetURL  // targetURL이 있으면 해당 URL로 이동
            } else {
                uri = "main"  // targetURL이 없으면 main으로 이동
            }
        } else {
            uri = ""  // Member-Code가 없으면 기본 페이지
        }

        let fullURL = baseURL.appendingPathComponent(uri)
        let request = URLRequest(url: fullURL)
        webView.load(request)

        // localStorage에 Member-Code 저장 후 페이지 이동
        if let memberCode = memberCode {
            let script = """
            localStorage.setItem('memberCode', '\(memberCode)');
            window.location.href = '\(fullURL.absoluteString)';
            """
            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    print("Error setting Member-Code before page load: \(error.localizedDescription)")
                } else {
                    print("✅ Member-Code 저장 완료 후 페이지 이동: \(fullURL.absoluteString)")
                }
            }
        }
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
        let nsError = error as NSError
        
        // "프레임 로드 중단됨" 에러 무시
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            return
        }
        activityIndicator.stopAnimating()
        showErrorAlert(message: "페이지를 로드할 수 없습니다. 네트워크 상태를 확인해주세요.")
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url , url.absoluteString.contains("kauth") {
            // 카카오톡 실행 가능 여부 확인 후 실행
            print("실행해줘잉 ㅠㅜ")
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }
        }
        
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
                if let memberCode = self?.decodeAuthToken(authToken: authToken) {
                    self?.storeMemberCodeInApp(memberCode)
                    self?.sendFCMTokenToServer(memberCode: memberCode, fcmToken: fcmToken)
                } else {
                    print("Failed to decode authToken.")
                }
            }
        }
    }
    private func storeMemberCodeInApp(_ memberCode: String) {
           UserDefaults.standard.set(memberCode, forKey: "Member-Code")
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
