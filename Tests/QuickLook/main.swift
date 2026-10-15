import Cocoa
import Quartz

/// An actual Quick Look service probe, with its own window kept outside every screen.
final class OffscreenWindow: NSWindow {
	override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect { frameRect }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let preview = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), style: .normal)!
let window = OffscreenWindow(
	contentRect: NSRect(x: -100_000, y: -100_000, width: 900, height: 700),
	styleMask: .borderless,
	backing: .buffered,
	defer: false
)
window.contentView = preview
window.orderBack(nil)
let liveCheck = CommandLine.arguments.contains("--live-check")
let paths = CommandLine.arguments.dropFirst().filter { $0 != "--live-check" }
for (index, path) in paths.enumerated() {
	preview.previewItem = URL(fileURLWithPath: path) as NSURL
	preview.refreshPreviewItem()
	let deadline = Date().addingTimeInterval(3)
	while Date() < deadline {
		RunLoop.current.run(until: Date().addingTimeInterval(0.05))
	}
	if liveCheck, index == 0 {
		// --live-check is used only with this test suite's disposable Markdown fixture.
		let url = URL(fileURLWithPath: path)
		let source = try String(contentsOf: url, encoding: .utf8)
		try (source + "\n## Live update\n").write(to: url, atomically: true, encoding: .utf8)
		let refreshedDeadline = Date().addingTimeInterval(3)
		while Date() < refreshedDeadline {
			RunLoop.current.run(until: Date().addingTimeInterval(0.05))
		}
	}
	print("Requested installed preview: \(URL(fileURLWithPath: path).lastPathComponent)")
}

preview.close()
window.orderOut(nil)
