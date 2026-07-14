import Foundation
import os.log

class MarkdownPreview: Preview {
	private let chromaStylesheetURL = Bundle.main.url(
		forResource: "shared-chroma",
		withExtension: "css"
	)
	private let mainStylesheetURL = Bundle.main.url(
		forResource: "markdown-main",
		withExtension: "css"
	)
	private let mermaidScriptURL = Bundle.main.url(
		forResource: "markdown-mermaid.min",
		withExtension: "js"
	)

	required init() {}

	private func getHTML(file: File) throws -> String {
		var source: String
		do {
			source = try file.read()
		} catch {
			os_log(
				"Could not read Markdown file: %{public}s",
				log: Log.parse,
				type: .error,
				error.localizedDescription
			)
			throw error
		}

		do {
			let html = try HTMLRenderer.renderMarkdown(source)
			return "<div class=\"markdown-body\">\(html)</div>"
		} catch {
			os_log(
				"Could not generate Markdown HTML: %{public}s",
				log: Log.render,
				type: .error,
				error.localizedDescription
			)
			throw error
		}
	}

	private func getStylesheets() -> [Stylesheet] {
		var stylesheets = [Stylesheet]()

		// Main Markdown stylesheet
		if let mainStylesheetURL = mainStylesheetURL {
			stylesheets.append(Stylesheet(url: mainStylesheetURL))
		} else {
			os_log("Could not find main Markdown stylesheet", log: Log.render, type: .error)
		}

		// Chroma stylesheet (for code syntax highlighting)
		if let chromaStylesheetURL = chromaStylesheetURL {
			stylesheets.append(Stylesheet(url: chromaStylesheetURL))
		} else {
			os_log("Could not find Chroma stylesheet", log: Log.render, type: .error)
		}

		return stylesheets
	}

	// The mermaid runtime is large; only inject it when the rendered HTML
	// actually contains a diagram. Detection uses a sentinel data attribute
	// emitted only by the Go-side mermaid renderer — users can't forge it
	// through markdown because raw HTML is escaped by goldmark.
	//
	// MUST stay in sync with `MermaidBlockOpenTag` in HTMLConverter/mermaid.go.
	// A Go-side test (`TestMermaidBlockOpenTagContainsSentinel`) pins the
	// sentinel literal so it can't drift unnoticed.
	private static let mermaidSentinel = "data-glance-mermaid=\"1\""

	private func getScripts(html: String) -> [Script] {
		var scripts = [Script]()

		guard html.contains(Self.mermaidSentinel) else {
			return scripts
		}

		if let mermaidScriptURL = mermaidScriptURL {
			scripts.append(Script(url: mermaidScriptURL))
		} else {
			os_log("Could not find Mermaid script", log: Log.render, type: .error)
			return scripts
		}

		// Theme follows prefers-color-scheme to match the markdown stylesheet.
		// `mermaid.run()` is called directly instead of relying on
		// `startOnLoad`, because the legacy WebView's DOMContentLoaded timing
		// is racy when scripts are emitted at the end of <body>.
		// `securityLevel: 'strict'` is pinned explicitly to make the safety
		// contract local to this file rather than implicit in mermaid's
		// default. `.catch` keeps a single malformed diagram from killing
		// sibling diagrams and surfaces parse errors in the WebView console.
		let initScript = """
		(function() {
			var isDark = window.matchMedia
				&& window.matchMedia('(prefers-color-scheme: dark)').matches;
			mermaid.initialize({
				startOnLoad: false,
				securityLevel: 'strict',
				theme: isDark ? 'dark' : 'default'
			});
			mermaid.run({ suppressErrors: true }).catch(function(e) {
				console.error('mermaid.run failed:', e);
			});
		})();
		"""
		scripts.append(Script(content: initScript))

		return scripts
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		let html = try getHTML(file: file)
		return WebPreviewVC(
			html: html,
			stylesheets: getStylesheets(),
			scripts: getScripts(html: html)
		)
	}
}
