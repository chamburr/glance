import Foundation

class JupyterPreview: Preview {
	private let chromaStylesheetURL = Bundle.main.url(
		forResource: "shared-chroma",
		withExtension: "css"
	)
	private let katexAutoRenderScriptURL = Bundle.main.url(
		forResource: "jupyter-katex-auto-render.min",
		withExtension: "js"
	)
	private let katexScriptURL = Bundle.main.url(
		forResource: "jupyter-katex.min",
		withExtension: "js"
	)
	private let katexStylesheetURL = Bundle.main.url(
		forResource: "jupyter-katex.min",
		withExtension: "css"
	)
	private let mainStylesheetURL = Bundle.main.url(
		forResource: "jupyter-main",
		withExtension: "css"
	)

	required init() {}

	private func getHTML(file: File) throws -> String {
		var source: String
		do {
			source = try file.read()
		} catch {
			Log.parse.error(
				"Could not read Jupyter Notebook file: \(error.localizedDescription, privacy: .public)"
			)
			throw error
		}

		do {
			return try HTMLRenderer.renderNotebook(source)
		} catch {
			Log.render.error(
				"Could not generate Jupyter Notebook HTML: \(error.localizedDescription, privacy: .public)"
			)
			throw error
		}
	}

	private func getStylesheets() -> [Stylesheet] {
		var stylesheets = [Stylesheet]()

		// Main Jupyter stylesheet (overrides and additions for nbtohtml stylesheet)
		if let mainStylesheetURL {
			stylesheets.append(Stylesheet(url: mainStylesheetURL))
		} else {
			Log.render.error("Could not find main Jupyter stylesheet")
		}

		// Chroma stylesheet (for code syntax highlighting)
		if let chromaStylesheetURL {
			stylesheets.append(Stylesheet(url: chromaStylesheetURL))
		} else {
			Log.render.error("Could not find Chroma stylesheet")
		}

		// KaTeX stylesheet (for rendering LaTeX math)
		if let katexStylesheetURL {
			stylesheets.append(Stylesheet(url: katexStylesheetURL))
		} else {
			Log.render.error("Could not find KaTeX stylesheet")
		}

		return stylesheets
	}

	private func getScripts() -> [Script] {
		var scripts = [Script]()

		// KaTeX library (for rendering LaTeX math)
		if let katexScriptURL {
			scripts.append(Script(url: katexScriptURL))
		} else {
			Log.render.error("Could not find KaTeX script")
		}

		// KaTeX auto-renderer (finds LaTeX math ond the page and calls KaTeX on it)
		if let katexAutoRenderScriptURL {
			scripts.append(Script(url: katexAutoRenderScriptURL))
		} else {
			Log.render.error("Could not find KaTeX auto-render script")
		}

		// Main script (calls the KaTeX auto-renderer)
		scripts.append(Script(content: "renderMathInElement(document.body);"))

		return scripts
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		WebPreviewVC(
			html: try getHTML(file: file),
			stylesheets: getStylesheets(),
			scripts: getScripts()
		)
	}
}
