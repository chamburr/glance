import Cocoa
import Foundation
import WebKit

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
func check(_ value: Bool, _ message: String) {
	if !value { fatalError(message) }
	print("PASS: " + message)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
	.appendingPathComponent("QLPlugin/Resources")
let web = WebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
let scripts = [
	"jupyter/jupyter-katex.min.js",
	"jupyter/jupyter-katex-auto-render.min.js",
	"markdown/markdown-math.js",
].map { "<script src=\"" + root.appendingPathComponent($0).path + "\"></script>" }.joined()
web.mainFrame.loadHTMLString(
	"<!DOCTYPE html><html><body><div class=\"markdown-body\"><p id=\"inline\">$x^2$</p><p>$$y=2$$</p><pre><code>$untouched$</code></pre></div>" +
		scripts + "</body></html>",
	baseURL: root
)
let deadline = Date().addingTimeInterval(30)
while Date() < deadline {
	RunLoop.current.run(until: Date().addingTimeInterval(0.05))
	if web
		.stringByEvaluatingJavaScript(from: "document.querySelectorAll('.katex').length === 2") ==
		"true" { break }
}

check(
	web
		.stringByEvaluatingJavaScript(from: "document.querySelectorAll('.katex').length === 2") ==
		"true",
	"inline and display math render"
)
check(
	web
		.stringByEvaluatingJavaScript(
			from: "document.querySelector('code').textContent === '$untouched$'"
		) ==
		"true",
	"code remains untouched"
)
