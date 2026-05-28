import Foundation

protocol WebAsset {
	init(content: String)
	init(url: URL)
	func getHTML() -> String
	/// Returns HTML with the asset content inlined (reads file contents for URL-based assets)
	func getInlineHTML() -> String
}
