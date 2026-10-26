// swiftformat:disable wrapMultilineStatementBraces
import Cocoa
import SQLite3
import WebKit

@main
struct RendererCheck {
	static func main() throws {
		_ = NSApplication.shared
		let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		func check(_ condition: Bool, _ message: String) {
			precondition(condition, message); print("PASS: \(message)")
		}
		func fixture(_ name: String, _ value: String) throws -> URL {
			let url = directory.appendingPathComponent(name)
			try value.write(to: url, atomically: true, encoding: .utf8)
			return url
		}
		let url = try fixture("sample.json", "{\"z\":2,\"a\":1}")
		let controller = try CodePreview().createPreviewVC(file: File(url: url))
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		controller.view.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
		controller.view.layoutSubtreeIfNeeded()
		let web = controller.view.subviews.compactMap { $0 as? WebView }.first!
		func evaluate(_ script: String) -> String { web
			.stringByEvaluatingJavaScript(from: script) ?? ""
		}
		let deadline = Date().addingTimeInterval(10)
		while evaluate("document.body ? document.body.textContent : ''")
			.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			Date() < deadline {
			RunLoop.current.run(until: Date().addingTimeInterval(0.05))
		}
		let text = evaluate("document.body.textContent")
		check(!text.isEmpty, "actual WebView document loaded")
		check(
			text.contains("\n") && text.contains("a") && text.contains("z"),
			"formatted source reaches real highlighted DOM"
		)
		check(evaluate("document.querySelectorAll('pre').length") != "0", "code block rendered")
		RunLoop.current.run(until: Date().addingTimeInterval(0.2))
		controller.view.displayIfNeeded()
		let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)!
		controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
		try bitmap.representation(using: .png, properties: [:])!
			.write(to: directory.appendingPathComponent("structured-data.png"))
		check(!window.isVisible, "window remains offscreen")
	}
}
