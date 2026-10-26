// swiftformat:disable wrapMultilineStatementBraces
import Cocoa
import os.log
import WebKit

/// Only bundled assets are served. Previews never fetch scripts, images or fonts from the network.
final class PreviewAssetHandler: NSObject, WKURLSchemeHandler {
	func webView(_: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
		guard let name = urlSchemeTask.request.url?.lastPathComponent,
		      let resource = Bundle.main.resourceURL?.appendingPathComponent(name),
		      let data = try? Data(contentsOf: resource)
		else {
			urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
			return
		}
		let types = [
			"css": "text/css",
			"js": "text/javascript",
			"woff2": "font/woff2",
			"woff": "font/woff",
			"ttf": "font/ttf",
		]
		guard types[resource.pathExtension] != nil else {
			urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
			return
		}
		let response = URLResponse(
			url: urlSchemeTask.request.url!,
			mimeType: types[resource.pathExtension] ??
				"application/octet-stream",
			expectedContentLength: data.count,
			textEncodingName: "utf-8"
		)
		urlSchemeTask.didReceive(response)
		urlSchemeTask.didReceive(data)
		urlSchemeTask.didFinish()
	}

	func webView(_: WKWebView, stop _: WKURLSchemeTask) {}
}

class WebPreviewVC: NSViewController, PreviewVC, WKNavigationDelegate {
	let html: String
	private let stylesheets: [Stylesheet]
	private let scripts: [Script]
	private(set) var webView: WKWebView!

	required convenience init(
		html: String,
		stylesheets: [Stylesheet] = [],
		scripts: [Script] = []
	) {
		self.init(
			nibName: nil,
			bundle: nil,
			html: html,
			stylesheets: stylesheets,
			scripts: scripts
		)
	}

	init(
		nibName nibNameOrNil: NSNib.Name?,
		bundle nibBundleOrNil: Bundle?,
		html: String,
		stylesheets: [Stylesheet] = [],
		scripts: [Script] = []
	) {
		self.html = html
		self.stylesheets = stylesheets
		self.scripts = scripts
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		configuration.setURLSchemeHandler(PreviewAssetHandler(), forURLScheme: "glance-resource")
		webView = WKWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = self
		webView.allowsMagnification = true
		webView.setValue(false, forKey: "drawsBackground")

		webView.frame = view.bounds
		webView.autoresizingMask = [.height, .width]
		view.addSubview(webView)
		webView.loadHTMLString(documentHTML, baseURL: URL(string: "glance-resource://bundle/"))
	}

	var documentHTML: String {
		let shared = Bundle.main.url(forResource: "shared-main", withExtension: "css")
		let links = (shared.map { [Stylesheet(url: $0)] } ?? []) + stylesheets
		return """
		<!doctype html><html><head><meta charset="utf-8">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src glance-resource: 'unsafe-inline'; style-src glance-resource: 'unsafe-inline'; img-src data:; font-src glance-resource: data:; connect-src 'none'; base-uri 'none'; form-action 'none'">
		\(links.map { $0.getHTML() }.joined(separator: "\n"))
		<style>:root { color-scheme: light dark; }</style></head><body><main>\(html)</main>
		\(scripts.map { $0.getHTML() }.joined(separator: "\n"))
		<script>if (window.glanceReady === undefined) window.glanceReady = true;</script></body></html>
		"""
	}

	func webView(
		_: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		// Anchor navigation stays inside the preview. Other links require the user's normal app.
		if navigationAction.navigationType == .linkActivated {
			if navigationAction.request.url?.fragment != nil,
			   navigationAction.request.url?.scheme == "glance-resource" {
				decisionHandler(.allow)
				return
			}
			if let url = navigationAction.request.url,
			   ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
				NSWorkspace.shared.open(url)
			}
			decisionHandler(.cancel)
			return
		}
		decisionHandler(.allow)
	}
}
