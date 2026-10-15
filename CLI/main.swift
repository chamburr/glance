// swiftformat:disable wrapMultilineStatementBraces
import AppKit
import MachO
import Quartz

var executableLength: UInt32 = 0
_ = _NSGetExecutablePath(nil, &executableLength)
var executableBuffer = [CChar](repeating: 0, count: Int(executableLength))
guard _NSGetExecutablePath(&executableBuffer, &executableLength) == 0 else {
	fputs("glance: cannot locate executable\n", stderr)
	exit(1)
}

let executableURL = URL(fileURLWithPath: String(cString: executableBuffer))
	.resolvingSymlinksInPath()
let containingAppURL = executableURL
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || arguments.contains("--help") {
	print("""
	Usage: glance [--check | --quick-look] FILE [FILE ...]

	Preview files in Glance using its shared renderers.
	--quick-look  Use the system Quick Look panel instead of the standalone window.
	--check   Report each file's content type without opening a window.
	--version Show the bundled application version.
	--help    Show this help.
	""")
	exit(0)
}

if arguments.first == "--version" {
	let version = Bundle(url: containingAppURL)?
		.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unbundled"
	print("Glance \(version)")
	exit(0)
}

let check = arguments.first == "--check"
let quickLook = arguments.first == "--quick-look"
let paths = (check || quickLook) ? Array(arguments.dropFirst()) : arguments
if paths.isEmpty {
	fputs("glance: supply at least one file\n", stderr); exit(2)
}

let urls = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
for url in urls where !FileManager.default.fileExists(atPath: url.path) {
	fputs("glance: file not found: \(url.path)\n", stderr)
	exit(1)
}

if check {
	for url in urls {
		let identifier = (try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier) ??
			"unknown"
		print("\(identifier)\t\(url.path)")
	}
	exit(0)
}

if !quickLook {
	let appURL = containingAppURL
	guard appURL.pathExtension == "app" else {
		fputs("glance: install the launcher inside Glance.app/Contents/Resources\n", stderr)
		exit(1)
	}
	let configuration = NSWorkspace.OpenConfiguration()
	var finished = false
	var failed = false
	NSWorkspace.shared
		.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
			if let error = error {
				fputs("glance: \(error.localizedDescription)\n", stderr); failed = true
			}
			finished = true
		}
	let deadline = Date().addingTimeInterval(15)
	while !finished,
	      Date() < deadline {
		RunLoop.current.run(until: Date().addingTimeInterval(0.02))
	}
	if !finished { fputs("glance: application launch timed out\n", stderr); exit(1) }
	exit(failed ? 1 : 0)
}

final class PreviewApplication: NSObject, NSApplicationDelegate, QLPreviewPanelDataSource,
	QLPreviewPanelDelegate {
	func applicationDidFinishLaunching(_: Notification) {
		guard let panel = QLPreviewPanel.shared() else { NSApp.terminate(nil)
			return
		}
		panel.dataSource = self
		panel.delegate = self
		panel.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
		urls.count
	}

	func previewPanel(
		_: QLPreviewPanel!,
		previewItemAt index: Int
	) -> QLPreviewItem! {
		urls[index] as NSURL
	}

	func windowWillClose(_: Notification) {
		NSApp.terminate(nil)
	}
}

let application = NSApplication.shared
let delegate = PreviewApplication()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
