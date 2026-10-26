// swiftformat:disable wrapMultilineStatementBraces
import Cocoa
import WebKit

NSApplication.shared.setActivationPolicy(.prohibited)
for key in ["previewFontSize", "previewWrap", "previewAppearance"] {
	UserDefaults.standard.removeObject(forKey: key)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
var failures = 0
func check(_ value: Bool, _ message: String) {
	if value { print("PASS: \(message)") } else { print("FAIL: \(message)"); failures += 1 }
}

func wait(_ condition: () -> Bool, seconds: TimeInterval = 15) -> Bool {
	let deadline = Date().addingTimeInterval(seconds)
	while !condition(),
	      Date() < deadline {
		RunLoop.current.run(until: Date().addingTimeInterval(0.02))
	}
	return condition()
}

func javascript(_ source: String, in controller: WebPreviewVC) -> Any? {
	var done = false
	var result: Any?
	controller.webView.evaluateJavaScript(source) { value, error in
		if let error = error { print("JavaScript: \(error)") }
		result = value; done = true
	}
	_ = wait { done }
	return result
}

func attach(_ controller: WebPreviewVC) -> NSWindow {
	let window = NSWindow(
		contentRect: NSRect(x: -100_000, y: -100_000, width: 900, height: 650),
		styleMask: [.titled],
		backing: .buffered,
		defer: false
	)
	window.isReleasedWhenClosed = false
	window.contentViewController = controller
	return window
}

func screenshot(_ controller: WebPreviewVC, name: String) {
	var done = false
	controller.webView.takeSnapshot(with: nil) { image, _ in
		defer { done = true }
		if let data = image?.tiffRepresentation,
		   let rep = NSBitmapImageRep(data: data),
		   let png = rep.representation(using: .png, properties: [:]) {
			try? png.write(to: directory.appendingPathComponent(name + ".png"))
		}
	}
	check(wait { done }, "Offscreen snapshot completed")
}

let controller = WebPreviewVC(html: "<h1>Bundled preview</h1><p>Offline renderer</p>")
let window = attach(controller)
check(
	wait { javascript("window.glanceReady === true", in: controller) as? Bool == true },
	"WKWebView actually renders"
)
check(
	javascript("document.querySelector('main h1').textContent", in: controller) as? String ==
		"Bundled preview",
	"Document content retained"
)
check(
	!controller.webView.configuration.websiteDataStore.isPersistent,
	"Website data is nonpersistent"
)
check(
	controller.documentHTML.contains("glance-resource://bundle/shared-main.css"),
	"Stylesheet uses bundled scheme"
)
_ = javascript(
	"window.blocked = false; document.addEventListener('securitypolicyviolation', e => { if (e.violatedDirective === 'connect-src') window.blocked = true; }); fetch('https://example.invalid/').catch(() => {}); true",
	in: controller
)
check(
	wait { javascript("window.blocked", in: controller) as? Bool == true },
	"CSP blocks an actual network request"
)
screenshot(controller, name: "web-modernization")
window.close()

let pending = WebPreviewVC(
	html: "<p>Async renderer</p>",
	scripts: [Script(content: "window.glanceReady = false;")]
)
let pendingWindow = attach(pending)
check(
	wait { javascript("window.glanceReady === false", in: pending) as? Bool == true },
	"Document wrapper preserves pending renderer state"
)
_ = javascript("window.glanceReady = true; true", in: pending)
check(
	wait { javascript("window.glanceReady === true", in: pending) as? Bool == true },
	"Async renderer can publish completion"
)
pendingWindow.close()

print("Failures: \(failures)")
exit(failures == 0 ? 0 : 1)
