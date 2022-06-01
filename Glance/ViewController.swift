import Cocoa

class ViewController: NSViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
	}

	@IBAction private func openSupportedFilesWindow(_: NSButton) {
		let supportedFilesWC = SupportedFilesWC(windowNibName: NSNib.Name("SupportedFilesWC"))
		supportedFilesWC.showWindow(nil)
	}
	
	@IBAction private func openGitHubRepository(_: NSButton) {
		websiteURL.open()
	}
}
