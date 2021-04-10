import Cocoa
import Foundation
import os.log
import WebKit

class WebPreviewVC: NSViewController, PreviewVC {
	private let html: String
	private let stylesheets: [Stylesheet]
	private let scripts: [Script]

	/// Stylesheet with CSS that applies to all file types
	private let sharedStylesheetURL = Bundle.main.url(
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
		self.stylesheets = [Stylesheet(url: sharedStylesheetURL!)] + stylesheets
		self.scripts = scripts
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		loadPreview()
	}

	private func loadPreview() {
		let webView = WebView(frame: view.bounds)
		webView.autoresizingMask = [.height, .width]

		view.addSubview(webView)

		let linkTags = stylesheets
			.map { $0.getHTML() }
			.joined(separator: "\n")
		let scriptTags = scripts
			.map { $0.getHTML() }
			.joined(separator: "\n")

		webView.mainFrame.loadHTMLString("""
		<!DOCTYPE html>
		<html>
			<head>
				<meta charset="utf-8" />
				<meta
					name="viewport"
					content="width=device-width, initial-scale=1, shrink-to-fit=no"
				/>
				\(linkTags)
			</head>
			<body>
				\(html)
				\(scriptTags)
			</body>
		</html>
		""", baseURL: Bundle.main.bundleURL)
	}
}
