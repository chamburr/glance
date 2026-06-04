import Cocoa
import Foundation
import WebKit

class WebPreviewVC: NSViewController, PreviewVC, WKNavigationDelegate {
	private let html: String
	private let stylesheets: [Stylesheet]
	private let scripts: [Script]
	private var webView: WKWebView?

	static let resourceBundle: Bundle = {
		let embeddedPluginBundle = Bundle.main.builtInPlugInsURL
			.flatMap { Bundle(url: $0.appendingPathComponent("QLPlugin.appex")) }
		let candidates = [
			Bundle(for: WebPreviewVC.self),
			Bundle(identifier: "com.chamburr.Glance.QLPlugin"),
			embeddedPluginBundle,
			Bundle.main,
		].compactMap { $0 }

		return candidates.first {
			$0.url(forResource: "shared-main", withExtension: "css") != nil
		} ?? Bundle(for: WebPreviewVC.self)
	}()

	/// Stylesheet with CSS that applies to all file types
	private let sharedStylesheetURL = WebPreviewVC.resourceBundle.url(
		forResource: "shared-main",
		withExtension: "css"
	)

	required convenience init(
		html: String,
		stylesheets: [Stylesheet] = [],
		scripts: [Script] = []
	) {
		self.init(nibName: nil, bundle: nil, html: html, stylesheets: stylesheets, scripts: scripts)
	}

	init(
		nibName nibNameOrNil: NSNib.Name?,
		bundle nibBundleOrNil: Bundle?,
		html: String,
		stylesheets: [Stylesheet] = [],
		scripts: [Script] = []
	) {
		self.html = html
		if let sharedStylesheetURL {
			self.stylesheets = [Stylesheet(url: sharedStylesheetURL)] + stylesheets
		} else {
			Log.render.error("Could not find shared stylesheet")
			self.stylesheets = stylesheets
		}
		self.scripts = scripts
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		webView?.navigationDelegate = nil
		webView?.stopLoading()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		loadPreview()
	}

	private func loadPreview() {
		let webView = WKWebView(frame: view.bounds)
		webView.autoresizingMask = [.height, .width]
		webView.underPageBackgroundColor = .clear
		webView.navigationDelegate = self
		self.webView = webView

		view.addSubview(webView)

		let linkTags = stylesheets
			.map { $0.getInlineHTML() }
			.joined(separator: "\n")
		let scriptTags = scripts
			.map { $0.getInlineHTML() }
			.joined(separator: "\n")

		let fullHTML = """
		<!DOCTYPE html>
		<html>
			<head>
				<meta charset="utf-8" />
				<meta
					name="viewport"
					content="width=device-width, initial-scale=1, shrink-to-fit=no"
				/>
				<meta
					http-equiv="Content-Security-Policy"
					content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data: file: blob:; font-src data: file:; media-src data: file: blob:; object-src 'none'; base-uri 'none'; form-action 'none'; connect-src 'none'"
				/>
				\(linkTags)
			</head>
			<body>
				\(html)
				\(scriptTags)
			</body>
		</html>
		"""
		webView.loadHTMLString(fullHTML, baseURL: Self.resourceBundle.resourceURL)
	}

	// MARK: - WKNavigationDelegate

	/// Reveal the web view once the content has finished loading to prevent flickering
	func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
		webView.alphaValue = 1
	}

	/// On navigation failure, show the web view anyway so the user sees something
	func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error) {
		webView.alphaValue = 1
	}

	func webView(
		_ webView: WKWebView,
		didFailProvisionalNavigation _: WKNavigation!,
		withError _: Error
	) {
		webView.alphaValue = 1
	}
}
