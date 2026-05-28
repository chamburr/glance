import Foundation

extension String {
	/// Cache for compiled regular expressions to avoid recompilation on every call
	private static let regexCache = NSCache<NSString, NSRegularExpression>()

	/// Returns all matches and capturing groups for the provided regular expression applied to the
	/// string
	///
	/// Source: https://stackoverflow.com/a/40040472/6767508
	func matchRegex(regex pattern: String) -> [[String]] {
		let regex: NSRegularExpression
		if let cached = Self.regexCache.object(forKey: pattern as NSString) {
			regex = cached
		} else {
			guard let compiled = try? NSRegularExpression(pattern: pattern, options: []) else {
				return []
			}
			Self.regexCache.setObject(compiled, forKey: pattern as NSString)
			regex = compiled
		}

		let nsString = self as NSString
		let results = regex.matches(
			in: self,
			options: [],
			range: NSRange(location: 0, length: nsString.length)
		)
		return results.map { result in
			(0 ..< result.numberOfRanges).map {
				result.range(at: $0).location != NSNotFound
					? nsString.substring(with: result.range(at: $0))
					: ""
			}
		}
	}
}
