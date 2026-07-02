import SwiftUI
import WebKit

struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: Message.markdown)
        userContentController.add(context.coordinator, name: Message.ready)
        userContentController.add(context.coordinator, name: Message.log)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.webView = webView
        context.coordinator.loadEditor()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateAppearance(colorScheme)
        context.coordinator.updateMarkdownIfNeeded(text)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Message.markdown
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Message.ready
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Message.log
        )
    }

    private enum Message {
        static let markdown = "turbodocMarkdown"
        static let ready = "turbodocReady"
        static let log = "turbodocLog"
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MarkdownEditor
        weak var webView: WKWebView?

        private var isReady = false
        private var editorMarkdown: String?
        private var appearance: ColorScheme?

        init(parent: MarkdownEditor) {
            self.parent = parent
        }

        func loadEditor() {
            guard let webView else { return }
            guard let indexURL = Self.editorIndexURL else {
                AppLogger.editor.fault("Bundled Markdown editor index.html is missing")
                return
            }

            webView.loadFileURL(
                indexURL,
                allowingReadAccessTo: indexURL.deletingLastPathComponent()
            )
        }

        func updateMarkdownIfNeeded(_ markdown: String) {
            guard isReady, markdown != editorMarkdown else { return }
            editorMarkdown = markdown
            evaluate("window.turbodocEditor.setMarkdown(\(Self.javaScriptString(markdown)));")
        }

        func updateAppearance(_ newAppearance: ColorScheme) {
            guard isReady, appearance != newAppearance else { return }
            appearance = newAppearance
            let value = newAppearance == .dark ? "dark" : "light"
            evaluate("window.turbodocEditor.setAppearance('\(value)');")
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case Message.ready:
                isReady = true
                AppLogger.editor.info("Markdown editor is ready")
                updateAppearance(parent.colorScheme)
                updateMarkdownIfNeeded(parent.text)

            case Message.markdown:
                guard
                    let payload = message.body as? [String: Any],
                    let markdown = payload["markdown"] as? String
                else {
                    AppLogger.editor.error("Editor sent an invalid Markdown payload")
                    return
                }

                editorMarkdown = markdown
                if parent.text != markdown {
                    parent.text = markdown
                }

            case Message.log:
                let payload = message.body as? [String: Any]
                let message = payload?["message"] as? String ?? "Unknown JavaScript error"
                AppLogger.editor.error("Markdown editor: \(message, privacy: .private)")

            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            AppLogger.editor.error(
                "Markdown editor navigation failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            AppLogger.editor.error(
                "Markdown editor failed to load: \(error.localizedDescription, privacy: .public)"
            )
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script) { _, error in
                if let error {
                    AppLogger.editor.error(
                        "Editor bridge command failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        private static var editorIndexURL: URL? {
            Bundle.main.url(
                forResource: "index",
                withExtension: "html",
                subdirectory: "MarkdownEditor"
            )
                ?? Bundle.main.url(
                    forResource: "index",
                    withExtension: "html",
                    subdirectory: "Resources/MarkdownEditor"
                )
                ?? Bundle.main.url(forResource: "index", withExtension: "html")
        }

        private static func javaScriptString(_ value: String) -> String {
            guard
                let data = try? JSONSerialization.data(withJSONObject: [value]),
                let json = String(data: data, encoding: .utf8)
            else {
                return "''"
            }
            return String(json.dropFirst().dropLast())
        }
    }
}
