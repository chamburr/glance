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
			"<script src=\"\(url.absoluteString)\"></script>"
		} else {
			"<script>\(content ?? "")</script>"
		}
	}
}
