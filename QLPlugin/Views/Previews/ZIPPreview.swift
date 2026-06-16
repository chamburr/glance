import Foundation
import ZIPFoundation

class ZIPPreview: Preview {
	let byteCountFormatter = ByteCountFormatter()
	private let maxEntryCount = 50_000

	required init() {}

	private func makeFileTree(from archive: Archive) throws -> (
		fileTree: FileTree,
		uncompressedSize: Int,
		compressedSize: Int
	) {
		let fileTree = FileTree()
		var uncompressedSize = 0
		var compressedSize = 0
		var entryCount = 0

		for entry in archive {
			guard entryCount < maxEntryCount else {
				throw ZIPPreviewError.entryCountLimitExceeded(maxEntryCount: maxEntryCount)
			}
			entryCount += 1

			let entryUncompressedSize = try Self.checkedArchiveSize(entry.uncompressedSize)
			let entryCompressedSize = try Self.checkedArchiveSize(entry.compressedSize)
			try Self.checkedAdd(entryUncompressedSize, to: &uncompressedSize)
			try Self.checkedAdd(entryCompressedSize, to: &compressedSize)

			if entry.path == "__MACOSX" || entry.path.hasPrefix("__MACOSX/") {
				continue
			}

			do {
				try fileTree.addNode(
					path: entry.path,
					isDirectory: entry.type == .directory,
					size: entryUncompressedSize,
					dateModified: entry.fileAttributes[.modificationDate] as? Date
				)
			} catch {
				Log.parse.error("\(error.localizedDescription, privacy: .private)")
			}
		}

		return (fileTree, uncompressedSize, compressedSize)
	}

	static func checkedArchiveSize(_ size: UInt64) throws -> Int {
		guard size <= UInt64(Int.max) else {
			throw ZIPPreviewError.metadataSizeLimitExceeded
		}
		return Int(size)
	}

	private static func checkedAdd(_ value: Int, to total: inout Int) throws {
		let result = total.addingReportingOverflow(value)
		guard !result.overflow else {
			throw ZIPPreviewError.metadataSizeLimitExceeded
		}
		total = result.partialValue
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
		let (fileTree, uncompressedSize, compressedSize) = try makeFileTree(from: archive)

		let labelText = """
		Compressed: \(byteCountFormatter.string(for: file.size) ?? "--")
		Uncompressed: \(byteCountFormatter.string(for: uncompressedSize) ?? "--")
		Compression ratio: \(compressionRatioText(compressed: compressedSize, uncompressed: uncompressedSize)) %
		"""

		return OutlinePreviewVC(rootNodes: fileTree.root.childrenList, labelText: labelText)
	}
}

enum ZIPPreviewError: LocalizedError {
	case entryCountLimitExceeded(maxEntryCount: Int)
	case metadataSizeLimitExceeded

	var errorDescription: String? {
		switch self {
			case let .entryCountLimitExceeded(maxEntryCount):
				NSLocalizedString(
					"ZIP archive metadata exceeds the \(maxEntryCount) entry preview limit",
					comment: ""
				)
			case .metadataSizeLimitExceeded:
				NSLocalizedString("ZIP archive metadata is too large to preview safely", comment: "")
		}
	}
}
