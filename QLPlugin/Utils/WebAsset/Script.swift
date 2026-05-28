import Foundation

class Script: WebAsset {
	private var content: String?
	private var url: URL?

	required init(content: String) {
		self.content = content
	}

	required init(url: URL) {
		self.url = url
	}

	func getHTML() -> String {
		if let url {
			"<script src=\"\(url.lastPathComponent)\"></script>"
		} else {
			"<script>\(content ?? "")</script>"
		}
	}

	func getInlineHTML() -> String {
		if let url, let fileContent = try? String(contentsOf: url, encoding: .utf8) {
			"<script>\(fileContent)</script>"
		} else {
			"<script>\(content ?? "")</script>"
		}
	}
}
