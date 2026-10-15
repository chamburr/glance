import os.log
import SwiftCSV

class TSVPreview: Preview {
	required init() {}

	func createPreviewVC(file: File) throws -> PreviewVC {
		// Read and parse TSV file
		var csv: CSV
		do {
			csv = try CSV(
				url: file.url,
				delimiter: file.url.pathExtension.lowercased() == "csv" ? "," : "\t"
			)
		} catch {
			os_log(
				"Could not parse TSV file: %{public}s",
				log: Log.parse,
				type: .error,
				error.localizedDescription
			)
			throw error
		}

		let rows = try EnumeratedView(
			header: csv.header,
			text: try file.read(),
			delimiter: file.url.pathExtension
				.lowercased() == "csv" ? "," : "\t",
			limitTo: 5001,
			loadColumns: false
		)
		return TablePreviewVC(headers: csv.header, cells: rows.rows)
	}
}
