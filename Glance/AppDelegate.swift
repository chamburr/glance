import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
	private var mainWindowController: NSWindowController?
	private var statusItem: NSStatusItem?

	func applicationDidFinishLaunching(_: Notification) {
		setUpStatusItem()
	}

	func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { false }

	private func setUpStatusItem() {
		let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
		statusItem.button?.image = NSImage(
			systemSymbolName: "eye",
			accessibilityDescription: "Glance"
		)
		statusItem.button?.image?.isTemplate = true
		statusItem.button?.toolTip = "Glance"
		statusItem.menu = makeStatusMenu()

		self.statusItem = statusItem
	}

	private func makeStatusMenu() -> NSMenu {
		let menu = NSMenu()
		menu.addItem(NSMenuItem(
			title: "Open Glance",
			action: #selector(openMainWindow),
			keyEquivalent: ""
		))
		menu.addItem(NSMenuItem(
			title: "Supported Files",
			action: #selector(openSupportedFilesWindow),
			keyEquivalent: ""
		))
		menu.addItem(NSMenuItem(
			title: "Open GitHub Repository",
			action: #selector(openGitHubRepository),
			keyEquivalent: ""
		))
		menu.addItem(.separator())
		menu.addItem(NSMenuItem(
			title: "Quit Glance",
			action: #selector(quitGlance),
			keyEquivalent: "q"
		))

		for item in menu.items where item.action != nil {
			item.target = self
		}

		return menu
	}

	@objc private func openMainWindow() {
		NSApp.activate(ignoringOtherApps: true)

		if let window = existingMainWindow() {
			window.deminiaturize(nil)
			window.makeKeyAndOrderFront(nil)
			return
		}

		let storyboard = NSStoryboard(name: "Main", bundle: nil)
		if let windowController = storyboard.instantiateInitialController() as? NSWindowController {
			mainWindowController = windowController
			windowController.showWindow(nil)
			windowController.window?.makeKeyAndOrderFront(nil)
		}
	}

	@objc private func openSupportedFilesWindow() {
		NSApp.activate(ignoringOtherApps: true)
		SupportedFilesWC.shared.showSupportedFilesWindow()
	}

	@objc private func openGitHubRepository() {
		websiteURL.open()
	}

	@objc private func quitGlance() {
		NSApp.terminate(nil)
	}

	private func existingMainWindow() -> NSWindow? {
		NSApp.windows.first { $0.title == "Glance" }
	}
}
