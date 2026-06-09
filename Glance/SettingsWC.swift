import Cocoa

final class SettingsWC: NSWindowController {
	static let shared = SettingsWC()

	private let hideDockIconCheckbox = NSButton(
		checkboxWithTitle: "Hide Dock icon",
		target: nil,
		action: nil
	)

	private init() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)
		window.title = "Settings"
		window.isReleasedWhenClosed = false
		window.center()

		super.init(window: window)

		setUpContent()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func showSettingsWindow() {
		syncState()
		NSApp.activate(ignoringOtherApps: true)
		showWindow(nil)
		window?.makeKeyAndOrderFront(nil)
	}

	// MARK: - Content Setup

	private func setUpContent() {
		guard let contentView = window?.contentView else { return }

		hideDockIconCheckbox.target = self
		hideDockIconCheckbox.action = #selector(hideDockIconChanged)

		let descriptionLabel = NSTextField(
			labelWithString: "The Dock icon is hidden when all windows are closed. Glance stays available from the menu bar."
		)
		descriptionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		descriptionLabel.textColor = .secondaryLabelColor
		descriptionLabel.lineBreakMode = .byWordWrapping
		descriptionLabel.maximumNumberOfLines = 0

		let stackView = NSStackView(views: [
			sectionLabel("General"),
			hideDockIconCheckbox,
			descriptionLabel
		])
		stackView.orientation = .vertical
		stackView.alignment = .leading
		stackView.spacing = 8
		stackView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(stackView)

		NSLayoutConstraint.activate([
			stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
			stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
			stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
		])
	}

	// MARK: - State

	private func syncState() {
		hideDockIconCheckbox.state = AppSettingsStore.shared.hideDockIcon ? .on : .off
	}

	@objc private func hideDockIconChanged(_ sender: NSButton) {
		AppSettingsStore.shared.hideDockIcon = sender.state == .on
		if let appDelegate = NSApp.delegate as? AppDelegate {
			appDelegate.updateDockIconVisibility()
		}
	}

	// MARK: - View Helpers

	private func sectionLabel(_ text: String) -> NSTextField {
		let textField = NSTextField(labelWithString: text)
		textField.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
		return textField
	}
}
