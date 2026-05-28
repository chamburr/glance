import Foundation
import HTMLConverter

enum HTMLRendererError {
	case rendererError(fileType: String, errorMessage: String)
}

extension HTMLRendererError: LocalizedError {
	var errorDescription: String? {
		switch self {
			case let .rendererError(fileType, errorMessage):
				NSLocalizedString(
					"Could not convert \(fileType) to HTML: \(errorMessage)",
					comment: ""
				)
		}
	}
}

enum HTMLRenderer {
	/// Throws an error if the return value indicates one. Because all `HTMLConverter` return values
	/// are C strings, errors are implemented as return values starting with "error: ".
	static func throwIfErrored(fileType: String, returnValue: String) throws {
		if returnValue.hasPrefix("error :") {
			let startIndex = returnValue.index(returnValue.startIndex, offsetBy: 7)
			let errorMessage = returnValue[startIndex ..< returnValue.endIndex]
			throw HTMLRendererError.rendererError(
				fileType: fileType,
				errorMessage: String(errorMessage)
			)
		}
	}

	/// Converts a code string to HTML with support for syntax highlighting.
	static func renderCode(_ source: String, lexer: String) throws -> String {
		let htmlCString = source.withCString { sourcePointer in
			lexer.withCString { lexerPointer in
				convertCodeToHTML(
					UnsafeMutablePointer<Int8>(mutating: sourcePointer),
					UnsafeMutablePointer<Int8>(mutating: lexerPointer)
				)
			}
		}
		let htmlString = try makeHTMLString(fileType: "code", htmlCString: htmlCString)
		try throwIfErrored(fileType: "code", returnValue: htmlString)
		return htmlString
	}

	/// Converts a Markdown string to HTML.
	static func renderMarkdown(_ source: String) throws -> String {
		let htmlCString = source.withCString { sourcePointer in
			convertMarkdownToHTML(UnsafeMutablePointer<Int8>(mutating: sourcePointer))
		}
		let htmlString = try makeHTMLString(fileType: "Markdown", htmlCString: htmlCString)
		try throwIfErrored(fileType: "Markdown", returnValue: htmlString)
		return htmlString
	}

	/// Converts a Jupyter Notebook JSON file to HTML.
	static func renderNotebook(_ source: String) throws -> String {
		let htmlCString = source.withCString { sourcePointer in
			convertNotebookToHTML(UnsafeMutablePointer<Int8>(mutating: sourcePointer))
		}
		let htmlString = try makeHTMLString(fileType: "Jupyter Notebook", htmlCString: htmlCString)
		try throwIfErrored(fileType: "Jupyter Notebook", returnValue: htmlString)
		return htmlString
	}

	private static func makeHTMLString(
		fileType: String,
		htmlCString: UnsafeMutablePointer<Int8>?
	) throws -> String {
		guard let htmlCString else {
			throw HTMLRendererError.rendererError(
				fileType: fileType,
				errorMessage: "renderer returned an empty response"
			)
		}

		defer { free(htmlCString) }
		return String(cString: htmlCString)
	}
}
