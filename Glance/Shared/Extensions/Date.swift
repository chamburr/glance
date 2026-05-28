import Foundation

extension Date {
	/// Thread-safe date formatter cached as a static constant to avoid repeated allocation
	private static let dateStringFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()

	/// Converts the `Date` to a `yyyy-MM-dd` string
	func toDateString() -> String {
		Self.dateStringFormatter.string(from: self)
	}
}
