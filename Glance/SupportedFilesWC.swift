import Cocoa

class SupportedFilesWC: NSWindowController {
	static let shared = SupportedFilesWC(windowNibName: NSNib.Name("SupportedFilesWC"))

	func showSupportedFilesWindow() {
		showWindow(nil)
		window?.makeKeyAndOrderFront(nil)
	}
}
