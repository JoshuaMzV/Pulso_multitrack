import SwiftUI
import WebKit

@MainActor
struct FullPulsoView: View {
    @AppStorage("pulso.server.url") private var server = ""
    @State private var address = ""
    @State private var configuring = false

    private var validatedAddress: URL? {
        Self.serverURL(address)
    }

    private static func serverURL(_ value: String) -> URL? {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = input.contains("://") ? input : "https://" + input
        guard let parts = URLComponents(string: text),
              parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        return parts.url
    }

    var body: some View {
        if let url = Self.serverURL(server) {
            PulsoWebView(url: url, configure: openSettings)
                .id(url)
                .sheet(isPresented: $configuring) { connectionForm }
        } else {
            connectionForm
        }
    }

    private func openSettings() {
        address = server
        configuring = true
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PULSO").font(.largeTitle.bold())
            Text("Introduce la dirección HTTPS de tu servidor PULSO.")
            TextField("https://servidor.example", text: $address)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Abrir PULSO") {
                guard let url = validatedAddress else { return }
                server = url.absoluteString
                configuring = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(validatedAddress == nil)
            if configuring {
                Button("Cancelar") { configuring = false }
            }
        }
        .padding(24)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PulsoWebView: UIViewRepresentable {
    let url: URL
    let configure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(url: url, configure: configure) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        let gesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.settings(_:)))
        gesture.numberOfTouchesRequired = 3
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let url: URL
        let configure: () -> Void

        init(url: URL, configure: @escaping () -> Void) {
            self.url = url
            self.configure = configure
        }

        @objc func settings(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { configure() }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            configure()
        }
    }
}
