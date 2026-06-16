import Foundation
import SwiftCSV

class TSVPreview: Preview {
	static let defaultMaxFileSize = 25 * 1_024 * 1_024
	static let defaultMaxRows = 5_000
	static let defaultMaxColumns = 512

	private let maxFileSize: Int
	private let maxRows: Int
	private let maxColumns: Int

	required convenience init() {
		self.init(
			maxFileSize: TSVPreview.defaultMaxFileSize,
			maxRows: TSVPreview.defaultMaxRows,
			maxColumns: TSVPreview.defaultMaxColumns
		)
	}

	init(maxFileSize: Int, maxRows: Int, maxColumns: Int) {
		self.maxFileSize = max(0, maxFileSize)
		self.maxRows = max(0, maxRows)
		self.maxColumns = max(0, maxColumns)
	}

	convenience init(maxRows: Int, maxColumns: Int) {
		self.init(
			maxFileSize: TSVPreview.defaultMaxFileSize,
			maxRows: maxRows,
			maxColumns: maxColumns
		)
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		guard file.size <= maxFileSize else {
			throw TSVPreviewError.fileSizeLimitExceeded(maxSize: maxFileSize)
		}

		// Read and parse TSV file
		var csv: NamedCSV
		do {
			let contents = try file.read()
			try validateHeaderColumnCount(in: contents)
			csv = try NamedCSV(
				string: contents,
				delimiter: .tab,
				loadColumns: false,
				rowLimit: maxRows
			)
		} catch {
			Log.parse
				.error("Could not parse TSV file: \(error.localizedDescription, privacy: .private)")
			throw error
		}

		return TablePreviewVC(headers: csv.header, cells: csv.rows)
	}

	private func validateHeaderColumnCount(in contents: String) throws {
		let columnCount = headerColumnCount(in: contents)
		guard columnCount <= maxColumns else {
			throw TSVPreviewError.columnLimitExceeded(maxColumns: maxColumns)
		}
	}

	private func headerColumnCount(in contents: String) -> Int {
		guard !contents.isEmpty else {
			return 0
		}

		var columnCount = 1
		var isInsideQuotes = false
		var index = contents.startIndex
		while index < contents.endIndex {
			let character = contents[index]
			if character == "\n" || character == "\r" {
				break
			}
			if character == "\"" {
				let nextIndex = contents.index(after: index)
				if isInsideQuotes, nextIndex < contents.endIndex, contents[nextIndex] == "\"" {
					index = nextIndex
				} else {
					isInsideQuotes.toggle()
				}
			} else if character == "\t", !isInsideQuotes {
				columnCount += 1
			}
			index = contents.index(after: index)
		}
		return columnCount
	}
}

private enum TSVPreviewError: LocalizedError {
	case fileSizeLimitExceeded(maxSize: Int)
	case columnLimitExceeded(maxColumns: Int)

	var errorDescription: String? {
		switch self {
			case let .fileSizeLimitExceeded(maxSize):
				NSLocalizedString(
					"TSV file exceeds the \(maxSize) byte preview limit",
					comment: ""
				)
			case let .columnLimitExceeded(maxColumns):
				NSLocalizedString(
					"TSV header exceeds the \(maxColumns) column preview limit",
					comment: ""
				)
		}
	}
}
