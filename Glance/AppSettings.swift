import Cocoa

enum AppSettings {
	private static let hideDockIconKey = "hideDockIcon"

	static var hideDockIcon: Bool {
		get { UserDefaults.standard.bool(forKey: hideDockIconKey) }
		set { UserDefaults.standard.set(newValue, forKey: hideDockIconKey) }
	}

	static func applyDockIconPreference() {
		NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
	}
}
