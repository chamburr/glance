import os.log
import SwiftCSV

class TSVPreview: Preview {
	required init() {}

	func createPreviewVC(file: File) throws -> PreviewVC {
		// Read and parse TSV file
		var csv: NamedCSV
		do {
			csv = try NamedCSV(url: file.url, delimiter: .tab)
		} catch {
			os_log(
				"Could not parse TSV file: %{public}s",
				log: Log.parse,
				type: .error,
				error.localizedDescription
			)
			throw error
		}

		return TablePreviewVC(headers: csv.header, cells: csv.rows)
	}
}
