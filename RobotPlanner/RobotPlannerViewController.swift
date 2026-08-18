import UIKit
import WebKit

final class RobotPlannerViewController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var bridge: RobotBridge!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.canCancelContentTouches = true
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        bridge = RobotBridge(webView: webView, host: self)
        contentController.add(bridge, name: "robotBridge")

        guard let url = Bundle.main.url(forResource: "index", withExtension: "html") else {
            assertionFailure("index.html missing from app bundle")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: Bundle.main.bundleURL)
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "robotBridge")
    }
}
