import Foundation
import OSLog

enum Log {
	// Subsystems
	static let subsystem = Bundle.main.bundleIdentifier ?? "com.chamburr.Glance"

	// Categories
	static let general = Logger(subsystem: subsystem, category: "general")
	static let parse = Logger(subsystem: subsystem, category: "parse")
	static let render = Logger(subsystem: subsystem, category: "render")
}
