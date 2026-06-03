import Foundation

class CodePreview: Preview {
	private let chromaStylesheetURL = Bundle.main.url(
		forResource: "shared-chroma",
		withExtension: "css"
	)

	required init() {}

	func getSource(file: File) throws -> String {
		try file.read()
	}

	private func getHTML(file: File) throws -> String {
		var source: String
		do {
			source = try getSource(file: file)
		} catch {
			Log.parse
				.error("Could not read code file: \(error.localizedDescription, privacy: .private)")
			throw error
		}

		let lexer = PreviewSupport.getCodeLexer(fileURL: file.url)
		do {
			return try HTMLRenderer.renderCode(source, lexer: lexer)
		} catch {
			Log.render
				.error(
					"Could not generate code HTML: \(error.localizedDescription, privacy: .private)"
				)
			throw error
		}
	}

	private func getStylesheets() -> [Stylesheet] {
		var stylesheets = [Stylesheet]()

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
