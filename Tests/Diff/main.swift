// swiftformat:disable wrapMultilineStatementBraces
// swiftformat:disable numberFormatting
import Cocoa
import WebKit

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
	precondition(condition(), message)
	checks += 1
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let patchURL = directory.appendingPathComponent("example.patch")
check(
	PreviewVCFactory.getPreviewInitializer(fileURL: patchURL) is DiffPreview.Type,
	"Patch routing"
)
check(
	PreviewVCFactory
		.getPreviewInitializer(fileURL: directory.appendingPathComponent("X.DIFF")) is DiffPreview
		.Type,
	"Diff routing"
)
let html = DiffPreview
	.renderHTML(
		source: "diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n-old\n+<script>alert(1)</script>\n"
	)
check(html.contains("diff-remove") && html.contains("diff-add"), "Change styles")
check(html.contains("&lt;script&gt;") && !html.contains("<script>"), "Escaping")
check(html.contains("diff-number\">1</span>"), "Line numbers")
check(
	DiffPreview.renderHTML(source: String(repeating: "+line\n", count: 12_010))
		.contains("Preview limit reached"),
	"Row limit"
)
check(
	!DiffPreview.renderHTML(source: "@@ -9223372036854775807 +1 @@\n-old\n+new")
		.contains("diff-remove\""),
	"Overflow handling"
)
check(
	DiffPreview.renderHTML(source: "diff --git a/a b/a\n+x\ndiff --git a/b b/b\n+y")
		.contains("Changed files"),
	"Multiple files"
)

// Instantiate the actual controller in an unshown, offscreen window.
_ = NSApplication.shared
let window = NSWindow(
	contentRect: NSRect(x: -100_000, y: -100_000, width: 900, height: 650),
	styleMask: [.borderless],
	backing: .buffered,
	defer: false
)
func capture(_ view: NSView, name: String) throws {
	view.layoutSubtreeIfNeeded()
	guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds),
	      let data = bitmap.representation(using: .png, properties: [:])
	else { preconditionFailure("Snapshot unavailable") }
	view.cacheDisplay(in: view.bounds, to: bitmap)
	try bitmap.representation(using: .png, properties: [:])!
		.write(to: directory.appendingPathComponent(name + ".png"))
	check(!data.isEmpty, "Snapshot produced")
}

try "diff --git a/example.swift b/example.swift\n--- a/example.swift\n+++ b/example.swift\n@@ -1,2 +1,2 @@\n-old value\n+<script>alert(1)</script>\n context\n"
	.write(
		to: patchURL,
		atomically: true,
		encoding: .utf8
	)
let controller = try DiffPreview().createPreviewVC(file: File(url: patchURL)) as! WebPreviewVC
window.contentViewController = controller
controller.view.layoutSubtreeIfNeeded()
let webView = controller.view.subviews.compactMap { $0 as? WebView }.first!
let deadline = Date().addingTimeInterval(15)
while webView
	.stringByEvaluatingJavaScript(from: "document.querySelectorAll('.diff-add').length") != "1",
	Date() < deadline {
	RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}

check(
	webView
		.stringByEvaluatingJavaScript(from: "document.querySelectorAll('.diff-add').length") == "1",
	"Actual legacy web renderer loads diff"
)
check(
	webView.stringByEvaluatingJavaScript(from: "document.querySelectorAll('script').length") == "0",
	"Escaped diff creates no script nodes"
)
check(
	webView
		.stringByEvaluatingJavaScript(
			from: "document.querySelector('.diff-add .diff-text').textContent"
		) ==
		"+<script>alert(1)</script>",
	"Literal patch text renders"
)
check(
	webView
		.stringByEvaluatingJavaScript(
			from: "document.querySelector('.diff-add .diff-number:nth-child(2)').textContent"
		) ==
		"1",
	"Actual new-side line number"
)
try capture(controller.view, name: "diff")
print("Passed \(checks) headless checks")
