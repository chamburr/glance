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
let scripts = ["markdown/markdown-callouts.js"]
	.map { "<script src=\"" + root.appendingPathComponent($0).path + "\"></script>" }.joined()
web.mainFrame.loadHTMLString(
	"<html><body><div class=\"markdown-body\"><blockquote><p>[!WARNING]\nCareful</p></blockquote><blockquote id=\"ordinary\"><p>Ordinary</p></blockquote><blockquote id=\"unknown\"><p>[!OTHER]\nText</p></blockquote><pre><code>[!NOTE]</code></pre></div>" +
		scripts + "</body></html>",
	baseURL: root
)
let deadline = Date().addingTimeInterval(30)
while Date() < deadline {
	RunLoop.current.run(until: Date().addingTimeInterval(0.05))
	if web
		.stringByEvaluatingJavaScript(
			from: "!!document.querySelector('.markdown-alert-warning[role=note]')"
		) ==
		"true" { break }
}

check(
	web
		.stringByEvaluatingJavaScript(
			from: "!!document.querySelector('.markdown-alert-warning[role=note]')"
		) ==
		"true",
	"warning callout accessible"
)
check(
	web
		.stringByEvaluatingJavaScript(
			from: "!document.querySelector('#ordinary').className && !document.querySelector('#unknown').className"
		) ==
		"true",
	"ordinary and unknown blockquotes untouched"
)
