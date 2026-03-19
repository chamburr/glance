import Foundation
import os.log
import SWCompression

class SevenZipPreview: Preview {
	let byteCountFormatter = ByteCountFormatter()

	required init() {}

	func createPreviewVC(file: File) throws -> PreviewVC {
		let archiveURL = URL(fileURLWithPath: file.path)
		let fileData = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
		let entries = try SevenZipContainer.info(container: fileData)

		let fileTree = FileTree()
		var totalUncompressed = 0

		for entry in entries {
			let size = entry.size ?? 0
			totalUncompressed += size
			let isDirectory = entry.type == .directory
			do {
				try fileTree.addNode(
					path: entry.name,
					isDirectory: isDirectory,
					size: size,
					dateModified: entry.modificationTime
				)
			} catch {
				os_log("%{public}s", log: Log.parse, type: .error, error.localizedDescription)
			}
		}

		let compressed = file.size
		let ratio = totalUncompressed == 0
			? 0.0
			: 100.0 - Double(compressed) / Double(totalUncompressed) * 100.0

		let labelText = """
		Compressed: \(byteCountFormatter.string(for: compressed) ?? "--")
		Uncompressed: \(byteCountFormatter.string(for: totalUncompressed) ?? "--")
		Compression ratio: \(String(format: "%.1f", ratio)) %
		"""

		return OutlinePreviewVC(rootNodes: fileTree.root.childrenList, labelText: labelText)
	}
}
