import Foundation

class Stylesheet: WebAsset {
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
			"<link rel=\"stylesheet\" type=\"text/css\" href=\"\(url.lastPathComponent)\" />"
		} else {
			"<style>\(content ?? "")</style>"
		}
	}

	func getInlineHTML() -> String {
		if let url, let fileContent = try? String(contentsOf: url, encoding: .utf8) {
			"<style>\(fileContent)</style>"
		} else {
			"<style>\(content ?? "")</style>"
		}
	}
}
