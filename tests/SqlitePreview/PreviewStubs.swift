import Cocoa
import os.log

protocol PreviewVC {}
protocol Preview { init(); func createPreviewVC(file: File) throws -> PreviewVC }
struct Script { let content: String }
struct Stylesheet { init(url _: URL) {} }
struct WebPreviewVC: PreviewVC { let html: String; init(
	html: String,
	stylesheets _: [Stylesheet] = [],
	scripts _: [Script] = []
) { self.html = html } }
enum Log { static let parse = OSLog.default; static let render = OSLog.default }
enum HTMLRenderer {
	static func renderCode(_ source: String, lexer _: String) throws -> String { source }
}
