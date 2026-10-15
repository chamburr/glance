import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
	private var previews: [PreviewWindowController] = []
	private var didLaunch = false
	private var openedDuringLaunch = false

	func applicationDidFinishLaunching(_: Notification) {
		didLaunch = true
		if openedDuringLaunch {
			let settingsWindows = NSApp.windows
				.filter { $0.contentViewController is ViewController }
			settingsWindows.forEach { $0.close() }
		}
	}

	func application(_: NSApplication, open urls: [URL]) {
		if !didLaunch { openedDuringLaunch = true }
		previews.removeAll { $0.window?.isVisible != true && $0.window?.isMiniaturized != true }
		for url in urls {
			do {
				let preview = try PreviewWindowController(fileURL: url)
				previews.append(preview)
				preview.onClose = { [weak self, weak preview] in
					self?.previews.removeAll { $0 === preview }
				}
				preview.window?.center()
				preview.showWindow(nil)
			} catch { NSAlert(error: error).runModal() }
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}
