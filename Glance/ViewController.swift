import Cocoa

class ViewController: NSViewController {
	@IBAction private func openSupportedFilesWindow(_: NSButton) {
		SupportedFilesWC.shared.showSupportedFilesWindow()
	}

	@IBAction private func openGitHubRepository(_: NSButton) {
		websiteURL.open()
	}
}
