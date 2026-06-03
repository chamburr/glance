import SwiftCSV

class TSVPreview: Preview {
	required init() {}

	func createPreviewVC(file: File) throws -> PreviewVC {
		// Read and parse TSV file
		var csv: NamedCSV
		do {
			csv = try NamedCSV(url: file.url, delimiter: .tab)
		} catch {
			Log.parse
				.error("Could not parse TSV file: \(error.localizedDescription, privacy: .private)")
			throw error
		}

		return TablePreviewVC(headers: csv.header, cells: csv.rows)
	}
}
