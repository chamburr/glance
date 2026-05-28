import Cocoa
import Foundation
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

	override func viewDidLoad() {
		super.viewDidLoad()
		loadPreview()
	}

	private func loadPreview() {
		let webView = WKWebView(frame: view.bounds)
		webView.autoresizingMask = [.height, .width]
		webView.setValue(false, forKey: "drawsBackground")
		view.addSubview(webView)

		let linkTags = stylesheets
			.map { $0.getHTML() }
			.joined(separator: "\n")
		let scriptTags = scripts
			.map { $0.getHTML() }
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
				\(linkTags)
			</head>
			<body>
				\(html)
				\(scriptTags)
			</body>
		</html>
		"""

		// WKWebView runs web content in a separate process. Using loadFileURL
		// with allowingReadAccessTo grants that process explicit file system
		// access, which is necessary in sandboxed Quick Look extensions.
		// Write the HTML to a temp file inside the bundle's resource directory
		// equivalent, then load it with access to the resources folder so
		// relative CSS/JS/font references resolve correctly.
		let resourceURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL

		do {
			let tempDir = FileManager.default.temporaryDirectory
				.appendingPathComponent("glance-preview", isDirectory: true)
			try FileManager.default.createDirectory(
				at: tempDir,
				withIntermediateDirectories: true
			)

			// Symlink the bundle resources into the temp directory so relative
			// href/src paths in <link> and <script> tags resolve correctly
			let resourceContents = try FileManager.default.contentsOfDirectory(
				at: resourceURL,
				includingPropertiesForKeys: nil
			)
			for resourceFile in resourceContents {
				let destination = tempDir.appendingPathComponent(resourceFile.lastPathComponent)
				// Remove existing symlinks/files before creating new ones
				try? FileManager.default.removeItem(at: destination)
				try FileManager.default.createSymbolicLink(
					at: destination,
					withDestinationURL: resourceFile
				)
			}

			let tempFile = tempDir.appendingPathComponent("preview.html")
			try fullHTML.write(to: tempFile, atomically: true, encoding: .utf8)
			webView.loadFileURL(tempFile, allowingReadAccessTo: tempDir)
		} catch {
			Log.render.error(
				"Failed to write temporary preview file: \(error.localizedDescription, privacy: .public)"
			)
			// Fall back to loadHTMLString with inlined content as last resort
			let inlineStyleTags = stylesheets
				.map { $0.getInlineHTML() }
				.joined(separator: "\n")
			let inlineScriptTags = scripts
				.map { $0.getInlineHTML() }
				.joined(separator: "\n")

			let fallbackHTML = """
			<!DOCTYPE html>
			<html>
				<head>
					<meta charset="utf-8" />
					<meta
						name="viewport"
						content="width=device-width, initial-scale=1, shrink-to-fit=no"
					/>
					\(inlineStyleTags)
				</head>
				<body>
					\(html)
					\(inlineScriptTags)
				</body>
			</html>
			"""
			webView.loadHTMLString(fallbackHTML, baseURL: nil)
		}
	}
}
