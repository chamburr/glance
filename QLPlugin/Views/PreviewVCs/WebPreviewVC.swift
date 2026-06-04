import Cocoa
import Foundation
import WebKit

class WebPreviewVC: NSViewController, PreviewVC, WKNavigationDelegate {
	private let html: String
	private let stylesheets: [Stylesheet]
	private let scripts: [Script]
	private var webView: WKWebView?
	private var previewFileURL: URL?

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

	deinit {
		webView?.navigationDelegate = nil
		webView?.stopLoading()
		if let previewFileURL {
			try? FileManager.default.removeItem(at: previewFileURL)
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		loadPreview()
	}

	/// Lazily created temp directory for preview HTML files, shared across all instances
	private static let previewDirectory: URL? = {
		let fileManager = FileManager.default
		let tempDir = fileManager.temporaryDirectory
			.appendingPathComponent("glance-preview", isDirectory: true)
		do {
			try fileManager.createDirectory(
				at: tempDir,
				withIntermediateDirectories: true
			)

			let tempContents = try fileManager.contentsOfDirectory(
				at: tempDir,
				includingPropertiesForKeys: nil
			)
			for tempFile in tempContents where tempFile.pathExtension == "html" {
				try? fileManager.removeItem(at: tempFile)
			}

			if let resourceURL = Bundle.main.resourceURL {
				let resourceContents = try fileManager.contentsOfDirectory(
					at: resourceURL,
					includingPropertiesForKeys: nil
				)
				for resourceFile in resourceContents {
					let destination = tempDir.appendingPathComponent(resourceFile.lastPathComponent)
					try? fileManager.removeItem(at: destination)
					try fileManager.copyItem(
						at: resourceFile,
						to: destination
					)
				}
			}
			return tempDir
		} catch {
			Log.render.error(
				"Failed to create preview directory: \(error.localizedDescription, privacy: .private)"
			)
			return nil
		}
	}()

	private func loadPreview() {
		let webView = WKWebView(frame: view.bounds)
		webView.autoresizingMask = [.height, .width]
		webView.underPageBackgroundColor = .clear
		webView.navigationDelegate = self
		self.webView = webView

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
		if let previewDir = Self.previewDirectory {
			do {
				let tempFile = previewDir.appendingPathComponent("\(UUID().uuidString).html")
				try fullHTML.write(to: tempFile, atomically: true, encoding: .utf8)
				previewFileURL = tempFile
				webView.loadFileURL(tempFile, allowingReadAccessTo: previewDir)
				return
			} catch {
				Log.render.error(
					"Failed to write preview HTML: \(error.localizedDescription, privacy: .private)"
				)
			}
		}

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
