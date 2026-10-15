// swiftformat:disable wrapMultilineStatementBraces
import Foundation
import ImageIO
import os.log
import UniformTypeIdentifiers

class MarkdownPreview: Preview {
	var imageRoot: URL?
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
			os_log(
				"Could not read Markdown file: %{public}s",
				log: Log.parse,
				type: .error,
				error.localizedDescription
			)
			throw error
		}

		do {
			let html = Self.inlineLocalImages(
				try HTMLRenderer.renderMarkdown(source),
				beside: file.url,
				allowedRoot: imageRoot
			)
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

	/// Embed only genuine images inside the document's directory, and only when the sandbox permits
	/// reading.
	static func inlineLocalImages(
		_ html: String,
		beside fileURL: URL,
		allowedRoot: URL? = nil
	) -> String {
		let expression = try! NSRegularExpression(pattern: #"(<img\s[^>]*?src=")([^"]+)(")"#)
		let root = (allowedRoot ?? fileURL.deletingLastPathComponent()).resolvingSymlinksInPath()
			.standardizedFileURL
		func properties(_ image: CGImageSource) -> [CFString: Any] {
			(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any]) ?? [:]
		}
		var output = html
		var budget = 20_000_000
		for match in expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
			.reversed() {
			guard let sourceRange = Range(match.range(at: 2), in: html) else { continue }
			let source = String(html[sourceRange]).replacingOccurrences(of: "&amp;", with: "&")
			guard let url = URL(string: source, relativeTo: fileURL)?.absoluteURL,
			      url.isFileURL else { continue }
			let resolved = url.resolvingSymlinksInPath().standardizedFileURL
			guard resolved.path.hasPrefix(root.path + "/"),
			      let size = try? resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize,
			      size <= 5_000_000, size <= budget,
			      let data = try? Data(contentsOf: resolved),
			      let image = CGImageSourceCreateWithData(data as CFData, nil),
			      let type = CGImageSourceGetType(image),
			      let width = properties(image)[kCGImagePropertyPixelWidth] as? Int,
			      let height = properties(image)[kCGImagePropertyPixelHeight] as? Int,
			      width > 0, height > 0, width <= 20_000_000 / height,
			      let mime = UTType(type as String)?.preferredMIMEType else { continue }
			budget -= data.count
			if let range = Range(match.range(at: 2), in: output) {
				output.replaceSubrange(
					range,
					with: "data:\(mime);base64,\(data.base64EncodedString())"
				)
			}
		}
		return output
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

	func createPreviewVC(file: File) throws -> PreviewVC {
		var stylesheets = getStylesheets()
		if let katex = Bundle.main.url(forResource: "jupyter-katex.min", withExtension: "css") {
			stylesheets.append(Stylesheet(url: katex))
		}
		return WebPreviewVC(
			html: try getHTML(file: file),
			stylesheets: stylesheets,
			scripts: [
				"jupyter-katex.min",
				"jupyter-katex-auto-render.min",
				"markdown-mermaid.min",
				"markdown-enhancements",
			].compactMap { name in
				Bundle.main.url(forResource: name, withExtension: "js").map { Script(url: $0) }
			},
			source: try file.read()
		)
	}
}
