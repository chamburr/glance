import Foundation
import ZIPFoundation

class ZIPPreview: Preview {
	let byteCountFormatter = ByteCountFormatter()

	required init() {}

	private func makeFileTree(from archive: Archive) -> (
		fileTree: FileTree,
		uncompressedSize: Int,
		compressedSize: Int
	) {
		let fileTree = FileTree()
		var uncompressedSize = 0
		var compressedSize = 0

		for entry in archive {
			uncompressedSize += Int(entry.uncompressedSize)
			compressedSize += Int(entry.compressedSize)

			if entry.path == "__MACOSX" || entry.path.hasPrefix("__MACOSX/") {
				continue
			}

			do {
				try fileTree.addNode(
					path: entry.path,
					isDirectory: entry.type == .directory,
					size: Int(entry.uncompressedSize),
					dateModified: entry.fileAttributes[.modificationDate] as? Date
				)
			} catch {
				Log.parse.error("\(error.localizedDescription, privacy: .private)")
			}
		}

		return (fileTree, uncompressedSize, compressedSize)
	}

	private func compressionRatioText(compressed: Int, uncompressed: Int) -> String {
		if uncompressed == 0 {
			return "0.0"
		}
		let ratio = 100.0 - Double(compressed) / Double(uncompressed) * 100.0
		return String(format: "%.1f", ratio)
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		let archive = try Archive(url: file.url, accessMode: .read)
		let (fileTree, uncompressedSize, compressedSize) = makeFileTree(from: archive)

		let labelText = """
		Compressed: \(byteCountFormatter.string(for: file.size) ?? "--")
		Uncompressed: \(byteCountFormatter.string(for: uncompressedSize) ?? "--")
		Compression ratio: \(compressionRatioText(compressed: compressedSize, uncompressed: uncompressedSize)) %
		"""

		return OutlinePreviewVC(rootNodes: fileTree.root.childrenList, labelText: labelText)
	}
}
