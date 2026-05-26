import Foundation
import os.log

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
			os_log(
				"Could not read code file: %{public}s",
				log: Log.parse,
				type: .error,
				error.localizedDescription
			)
			throw error
		}

		let lexer = PreviewSupport.getCodeLexer(fileURL: file.url)
		do {
			return try HTMLRenderer.renderCode(source, lexer: lexer)
		} catch {
			os_log(
				"Could not generate code HTML: %{public}s",
				log: Log.render,
				type: .error,
				error.localizedDescription
			)
			throw error
		}
	}

	private func getStylesheets() -> [Stylesheet] {
		var stylesheets = [Stylesheet]()

		// Chroma stylesheet (for code syntax highlighting)
		if let chromaStylesheetURL = chromaStylesheetURL {
			stylesheets.append(Stylesheet(url: chromaStylesheetURL))
		} else {
			os_log("Could not find Chroma stylesheet", log: Log.render, type: .error)
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
