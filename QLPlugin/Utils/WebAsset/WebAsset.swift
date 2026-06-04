import Foundation

protocol WebAsset {
	init(content: String)
	init(url: URL)
	func getHTML() -> String
	func getInlineHTML() -> String
}
