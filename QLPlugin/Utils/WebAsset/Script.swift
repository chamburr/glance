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
				do {
					return try String(contentsOf: url, encoding: .utf8)
				} catch {
					Log.render.error(
						"Could not read script asset \(url.path, privacy: .private): \(error.localizedDescription, privacy: .private)"
					)
					return ""
				}
		}
	}()

	required init(content: String) {
		source = .content(content)
	}

	required init(url: URL) {
		source = .url(url)
	}

	func getInlineHTML() -> String {
		getInlineHTML(nonce: nil)
	}

	func getInlineHTML(nonce: String?) -> String {
		let nonceAttribute = nonce.map { " nonce=\"\($0)\"" } ?? ""
		return "<script\(nonceAttribute)>\(inlineContent)</script>"
	}
}
