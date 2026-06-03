import Foundation

class MarkdownPreview: Preview {
	private let chromaStylesheetURL = Bundle.main.url(
		forResource: "shared-chroma",
		withExtension: "css"
	)
	private let mainStylesheetURL = Bundle.main.url(
		forResource: "markdown-main",
		withExtension: "css"
	)

	required init() {}

	private func getHTML(file: File) throws -> String {
		var source: String
		do {
			source = try file.read()
		} catch {
			Log.parse
				.error(
					"Could not read Markdown file: \(error.localizedDescription, privacy: .private)"
				)
			throw error
		}

		do {
			let html = try HTMLRenderer.renderMarkdown(source)
			return "<div class=\"markdown-body\">\(html)</div>"
		} catch {
			Log.render
				.error(
					"Could not generate Markdown HTML: \(error.localizedDescription, privacy: .private)"
				)
			throw error
		}
	}

	private func getStylesheets() -> [Stylesheet] {
		var stylesheets = [Stylesheet]()

		// Main Markdown stylesheet
		if let mainStylesheetURL {
			stylesheets.append(Stylesheet(url: mainStylesheetURL))
		} else {
			Log.render.error("Could not find main Markdown stylesheet")
		}

		// Chroma stylesheet (for code syntax highlighting)
		if let chromaStylesheetURL {
			stylesheets.append(Stylesheet(url: chromaStylesheetURL))
		} else {
			Log.render.error("Could not find Chroma stylesheet")
		}

		return stylesheets
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		WebPreviewVC(
			html: try getHTML(file: file),
			stylesheets: getStylesheets()
		)
	}
}
