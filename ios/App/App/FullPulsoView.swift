import UIKit
import WebKit

final class FullPulsoView: UIViewController, WKNavigationDelegate {
    private let storageKey = "pulso.server.url"
    private let browser: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        return WKWebView(frame: .zero, configuration: configuration)
    }()

    override func loadView() { view = browser }

    override func viewDidLoad() {
        super.viewDidLoad()
        browser.navigationDelegate = self
        browser.allowsBackForwardNavigationGestures = true
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(openSettings(_:)))
        gesture.numberOfTouchesRequired = 3
        gesture.cancelsTouchesInView = false
        browser.addGestureRecognizer(gesture)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard browser.url == nil, !browser.isLoading else { return }
        if let saved = UserDefaults.standard.string(forKey: storageKey), let url = serverURL(saved) {
            browser.load(URLRequest(url: url))
        } else {
            connectionForm()
        }
    }

    private func serverURL(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = value.contains("://") ? value : "https://" + value
        guard let parts = URLComponents(string: text),
              parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        return parts.url
    }

    @objc private func openSettings(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { connectionForm() }
    }

    private func connectionForm(message: String = "Introduce la dirección HTTPS de tu servidor PULSO.") {
        guard presentedViewController == nil else { return }
        let prompt = UIAlertController(title: "PULSO", message: message, preferredStyle: .alert)
        prompt.addTextField {
            $0.placeholder = "https://servidor.example"
            $0.text = UserDefaults.standard.string(forKey: self.storageKey)
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        prompt.addAction(UIAlertAction(title: "Abrir PULSO", style: .default) { [weak self, weak prompt] _ in
            guard let self else { return }
            guard let input = prompt?.textFields?.first?.text, let url = self.serverURL(input) else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.connectionForm(message: "Introduce una dirección HTTPS válida.")
                }
                return
            }
            UserDefaults.standard.set(url.absoluteString, forKey: self.storageKey)
            self.browser.load(URLRequest(url: url))
        })
        if browser.url != nil { prompt.addAction(UIAlertAction(title: "Cancelar", style: .cancel)) }
        present(prompt, animated: true)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let failure = error as NSError
        guard failure.domain != NSURLErrorDomain || failure.code != NSURLErrorCancelled else { return }
        connectionForm(message: "No se pudo abrir PULSO. Comprueba la dirección y que el iPad pueda llegar al servidor.")
    }
}
