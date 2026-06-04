import Foundation

final class Script: WebAsset {
	private enum Source {
		case content(String)
		case url(URL)
	}

	private let source: Source
	private lazy var inlineContent: String = {
		switch source {
			case let .content(content):
				return content
			case let .url(url):
				return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
		}
	}()

	required init(content: String) {
		source = .content(content)
	}

	required init(url: URL) {
		source = .url(url)
	}

	func getHTML() -> String {
		switch source {
			case let .content(content):
				return "<script>\(content)</script>"
			case let .url(url):
				return "<script src=\"\(url.lastPathComponent)\"></script>"
		}
	}

	func getInlineHTML() -> String {
		"<script>\(inlineContent)</script>"
	}
}
