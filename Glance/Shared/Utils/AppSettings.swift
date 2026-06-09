import Foundation

struct AppSettingsStore {
	static let sharedDefaultsSuiteName = "group.com.chamburr.glance"

	static let sharedDefaults: UserDefaults = {
		guard let defaults = UserDefaults(suiteName: sharedDefaultsSuiteName) else {
			fatalError("Failed to create UserDefaults with app group suite '\(sharedDefaultsSuiteName)'. Check that the app group is correctly configured.")
		}
		return defaults
	}()
	static let shared = AppSettingsStore(
		defaults: sharedDefaults,
		standardDefaults: .standard
	)

	private static let hideDockIconKey = "hideDockIcon"
	private static let standardDefaultsMigrationKey = "didMigrateStandardDefaults"

	private let defaults: UserDefaults
	private let standardDefaults: UserDefaults?

	init(defaults: UserDefaults, standardDefaults: UserDefaults? = nil) {
		self.defaults = defaults
		self.standardDefaults = standardDefaults
	}

	var hideDockIcon: Bool {
		get { defaults.bool(forKey: Self.hideDockIconKey) }
		nonmutating set {
			defaults.set(newValue, forKey: Self.hideDockIconKey)
		}
	}

	func migrateStandardDefaultsIfNeeded() {
		guard
			!defaults.bool(forKey: Self.standardDefaultsMigrationKey),
			let standardDefaults
		else { return }

		if
			defaults.object(forKey: Self.hideDockIconKey) == nil,
			standardDefaults.object(forKey: Self.hideDockIconKey) != nil
		{
			defaults.set(standardDefaults.bool(forKey: Self.hideDockIconKey), forKey: Self.hideDockIconKey)
		}

		defaults.set(true, forKey: Self.standardDefaultsMigrationKey)
	}
}
