import Foundation

extension Date {
	/// Date formatter cached as a static constant to avoid repeated allocation.
	private static let dateStringFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()

	private static let dateStringFormatterQueue = DispatchQueue(
		label: "com.chamburr.Glance.dateStringFormatter"
	)

	/// Converts the `Date` to a `yyyy-MM-dd` string
	func toDateString() -> String {
		Self.dateStringFormatterQueue.sync {
			Self.dateStringFormatter.string(from: self)
		}
	}
}
