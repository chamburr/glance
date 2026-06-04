import Foundation
import SWCompression

/// View controller for previewing tarballs (may be gzipped).
class TARPreview: Preview {
	let byteCountFormatter = ByteCountFormatter()

	required init() {}

	private func readArchiveData(file: File, isGzipped: Bool) throws -> Data {
		let fileData = try Data(contentsOf: file.url, options: .mappedIfSafe)
		if isGzipped {
			return try GzipArchive.unarchive(archive: fileData)
		}
		return fileData
	}

	private func makeFileTree(from entries: [TarEntryInfo]) -> FileTree {
		let fileTree = FileTree()

		for entry in entries {
			do {
				try fileTree.addNode(
					path: entry.name,
					isDirectory: entry.type == .directory,
					size: entry.size ?? 0,
					dateModified: entry.modificationTime
				)
			} catch {
				Log.parse.error("\(error.localizedDescription, privacy: .private)")
			}
		}

		return fileTree
	}

	private func compressionRatioText(compressed: Int, uncompressed: Int) -> String {
		if uncompressed == 0 {
			return "0.0"
		}
		let ratio = 100.0 - Double(compressed) / Double(uncompressed) * 100.0
		return String(format: "%.1f", ratio)
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		let normalizedPath = file.path.lowercased()
		let isGzipped = normalizedPath.hasSuffix(".tar.gz") || normalizedPath.hasSuffix(".tgz")

		let archiveData = try readArchiveData(file: file, isGzipped: isGzipped)
		let entries = try TarContainer.info(container: archiveData)
		let fileTree = makeFileTree(from: entries)
		var labelText =
			"\(isGzipped ? "Compressed" : "Size"): \(byteCountFormatter.string(for: file.size) ?? "--")"

		if isGzipped {
			labelText += """

			Uncompressed: \(byteCountFormatter.string(for: archiveData.count) ?? "--")
			Compression ratio: \(compressionRatioText(compressed: file.size, uncompressed: archiveData.count)) %
			"""
		}

		return OutlinePreviewVC(rootNodes: fileTree.root.childrenList, labelText: labelText)
	}
}
