import Foundation
import SWCompression

class SevenZipPreview: Preview {
	static let defaultMaxArchiveFileSize = 200 * 1_024 * 1_024
	static let defaultMaxMetadataHeaderSize = 8 * 1_024 * 1_024
	static let defaultMaxEntryCount = 50_000

	let byteCountFormatter = ByteCountFormatter()
	private let maxArchiveFileSize: Int
	private let maxMetadataHeaderSize: Int
	private let maxEntryCount: Int

	required convenience init() {
		self.init(
			maxArchiveFileSize: SevenZipPreview.defaultMaxArchiveFileSize,
			maxMetadataHeaderSize: SevenZipPreview.defaultMaxMetadataHeaderSize,
			maxEntryCount: SevenZipPreview.defaultMaxEntryCount
		)
	}

	init(maxArchiveFileSize: Int, maxMetadataHeaderSize: Int, maxEntryCount: Int) {
		self.maxArchiveFileSize = max(0, maxArchiveFileSize)
		self.maxMetadataHeaderSize = max(0, maxMetadataHeaderSize)
		self.maxEntryCount = max(0, maxEntryCount)
	}

	convenience init(maxArchiveFileSize: Int, maxEntryCount: Int) {
		self.init(
			maxArchiveFileSize: maxArchiveFileSize,
			maxMetadataHeaderSize: SevenZipPreview.defaultMaxMetadataHeaderSize,
			maxEntryCount: maxEntryCount
		)
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		guard file.size <= maxArchiveFileSize else {
			throw SevenZipPreviewError.archiveSizeLimitExceeded(maxSize: maxArchiveFileSize)
		}

		let archiveURL = URL(fileURLWithPath: file.path)
		let fileData = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
		try SevenZipMetadataPreflight(
			data: fileData,
			maxEntryCount: maxEntryCount,
			maxHeaderSize: maxMetadataHeaderSize
		).validate()
		let entries = try SevenZipContainer.info(container: fileData)
		guard entries.count <= maxEntryCount else {
			throw SevenZipPreviewError.entryCountLimitExceeded(maxEntryCount: maxEntryCount)
		}

		let fileTree = FileTree()
		var totalUncompressed = 0

		for entry in entries {
			let size = entry.size ?? 0
			guard size >= 0 else {
				throw SevenZipPreviewError.metadataSizeLimitExceeded
			}
			try Self.checkedAdd(size, to: &totalUncompressed)
			let isDirectory = entry.type == .directory
			do {
				try fileTree.addNode(
					path: entry.name,
					isDirectory: isDirectory,
					size: size,
					dateModified: entry.modificationTime
				)
			} catch {
				Log.parse.error("\(error.localizedDescription, privacy: .private)")
			}
		}

		let compressed = file.size
		let compressionRatio = totalUncompressed == 0
			? 0.0
			: 100.0 - Double(compressed) / Double(totalUncompressed) * 100.0

		let labelText = """
		Compressed: \(byteCountFormatter.string(for: compressed) ?? "--")
		Uncompressed: \(byteCountFormatter.string(for: totalUncompressed) ?? "--")
		Compression ratio: \(String(compressionRatio)) %
		"""

		return OutlinePreviewVC(rootNodes: fileTree.root.childrenList, labelText: labelText)
	}

	private static func checkedAdd(_ value: Int, to total: inout Int) throws {
		let result = total.addingReportingOverflow(value)
		guard !result.overflow else {
			throw SevenZipPreviewError.metadataSizeLimitExceeded
		}
		total = result.partialValue
	}
}

private enum SevenZipPreviewError: LocalizedError {
	case archiveSizeLimitExceeded(maxSize: Int)
	case entryCountLimitExceeded(maxEntryCount: Int)
	case metadataSizeLimitExceeded

	var errorDescription: String? {
		switch self {
			case let .archiveSizeLimitExceeded(maxSize):
				NSLocalizedString(
					"7z archive exceeds the \(maxSize) byte preview limit",
					comment: ""
				)
			case let .entryCountLimitExceeded(maxEntryCount):
				NSLocalizedString(
					"7z archive metadata exceeds the \(maxEntryCount) entry preview limit",
					comment: ""
				)
			case .metadataSizeLimitExceeded:
				NSLocalizedString("7z archive metadata is too large to preview safely", comment: "")
		}
	}
}

private enum SevenZipPreflightError: Error {
	case malformedHeader
}

private struct SevenZipMetadataPreflight {
	private let data: Data
	private let maxEntryCount: Int
	private let maxHeaderSize: Int

	init(data: Data, maxEntryCount: Int, maxHeaderSize: Int) {
		self.data = data
		self.maxEntryCount = maxEntryCount
		self.maxHeaderSize = maxHeaderSize
	}

	func validate() throws {
		do {
			try validateUnencodedHeader()
		} catch is SevenZipPreflightError {
			return
		}
	}

	private func validateUnencodedHeader() throws {
		guard data.count >= 32 else {
			return
		}
		guard Array(data[0..<6]) == [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C] else {
			return
		}
		guard let nextHeaderOffset = littleEndianUInt64(at: 12),
		      let nextHeaderSize = littleEndianUInt64(at: 20)
		else {
			throw SevenZipPreflightError.malformedHeader
		}
		guard nextHeaderSize <= UInt64(maxHeaderSize) else {
			throw SevenZipPreviewError.metadataSizeLimitExceeded
		}
		guard nextHeaderOffset <= UInt64(Int.max),
		      nextHeaderSize <= UInt64(Int.max)
		else {
			throw SevenZipPreviewError.metadataSizeLimitExceeded
		}

		let start = 32.addingReportingOverflow(Int(nextHeaderOffset))
		let end = start.partialValue.addingReportingOverflow(Int(nextHeaderSize))
		guard !start.overflow, !end.overflow else {
			throw SevenZipPreviewError.metadataSizeLimitExceeded
		}
		guard end.partialValue <= data.count else {
			throw SevenZipPreflightError.malformedHeader
		}

		var reader = SevenZipMetadataReader(
			data: data,
			offset: start.partialValue,
			endOffset: end.partialValue
		)
		let headerType = try reader.readByte()
		guard headerType == 0x01 else {
			return
		}
		try validateHeader(reader: &reader)
	}

	private func validateHeader(reader: inout SevenZipMetadataReader) throws {
		var type = try reader.readByte()

		if type == 0x02 {
			try skipProperties(reader: &reader)
			type = try reader.readByte()
		}
		if type == 0x04 {
			try skipStreamInfo(reader: &reader)
			type = try reader.readByte()
		}
		guard type == 0x05 else {
			return
		}

		let numFiles = try reader.readMultiByteInteger()
		guard numFiles <= maxEntryCount else {
			throw SevenZipPreviewError.entryCountLimitExceeded(maxEntryCount: maxEntryCount)
		}
	}

	private func skipStreamInfo(reader: inout SevenZipMetadataReader) throws {
		var type = try reader.readByte()

		if type == 0x06 {
			try skipPackInfo(reader: &reader)
			type = try reader.readByte()
		}

		var coderInfo = SevenZipCoderSummary.empty
		if type == 0x07 {
			coderInfo = try skipCoderInfo(reader: &reader)
			type = try reader.readByte()
		}

		if type == 0x08 {
			try skipSubstreamInfo(reader: &reader, coderInfo: coderInfo)
			type = try reader.readByte()
		}

		guard type == 0x00 else {
			throw SevenZipPreflightError.malformedHeader
		}
	}

	private func skipProperties(reader: inout SevenZipMetadataReader) throws {
		while true {
			let propertyType = try reader.readByte()
			if propertyType == 0x00 {
				return
			}
			let propertySize = try reader.readMultiByteInteger()
			try reader.skip(propertySize)
		}
	}

	private func skipPackInfo(reader: inout SevenZipMetadataReader) throws {
		_ = try reader.readMultiByteInteger()
		let numPackStreams = try validatedMetadataCount(reader.readMultiByteInteger())

		var type = try reader.readByte()
		if type == 0x09 {
			for _ in 0..<numPackStreams {
				_ = try reader.readMultiByteInteger()
			}
			type = try reader.readByte()
		}
		if type == 0x0A {
			let definedCount = try reader.readDefinedBitCount(count: numPackStreams)
			try reader.skipChecksums(count: definedCount)
			type = try reader.readByte()
		}
		guard type == 0x00 else {
			throw SevenZipPreflightError.malformedHeader
		}
	}

	private func skipCoderInfo(reader: inout SevenZipMetadataReader) throws -> SevenZipCoderSummary {
		let coderInfoType = try reader.readByte()
		guard coderInfoType == 0x0B else {
			throw SevenZipPreflightError.malformedHeader
		}

		let numFolders = try validatedMetadataCount(reader.readMultiByteInteger())
		let external = try reader.readByte()
		guard external == 0 else {
			throw SevenZipPreflightError.malformedHeader
		}

		var outputStreamsByFolder = [Int]()
		for _ in 0..<numFolders {
			outputStreamsByFolder.append(try skipFolder(reader: &reader))
		}

		var type = try reader.readByte()
		guard type == 0x0C else {
			throw SevenZipPreflightError.malformedHeader
		}

		for outputStreams in outputStreamsByFolder {
			for _ in 0..<outputStreams {
				_ = try reader.readMultiByteInteger()
			}
		}

		type = try reader.readByte()
		if type == 0x0A {
			let definedCount = try reader.readDefinedBitCount(count: numFolders)
			try reader.skipChecksums(count: definedCount)
			type = try reader.readByte()
		}
		guard type == 0x00 else {
			throw SevenZipPreflightError.malformedHeader
		}

		return SevenZipCoderSummary(numFolders: numFolders)
	}

	private func skipFolder(reader: inout SevenZipMetadataReader) throws -> Int {
		let numCoders = try validatedMetadataCount(reader.readMultiByteInteger())
		var totalInputStreams = 0
		var totalOutputStreams = 0

		for _ in 0..<numCoders {
			let flags = try reader.readByte()
			guard flags & 0xC0 == 0 else {
				throw SevenZipPreflightError.malformedHeader
			}

			let idSize = Int(flags & 0x0F)
			let isComplex = flags & 0x10 != 0
			let hasAttributes = flags & 0x20 != 0
			try reader.skip(idSize)

			let inputStreams = isComplex ? try reader.readMultiByteInteger() : 1
			let outputStreams = isComplex ? try reader.readMultiByteInteger() : 1
			totalInputStreams = try validatedMetadataCount(
				checkedAdd(totalInputStreams, inputStreams)
			)
			totalOutputStreams = try validatedMetadataCount(
				checkedAdd(totalOutputStreams, outputStreams)
			)

			if hasAttributes {
				let propertiesSize = try reader.readMultiByteInteger()
				try reader.skip(propertiesSize)
			}
		}

		guard totalOutputStreams > 0 else {
			throw SevenZipPreflightError.malformedHeader
		}
		let numBindPairs = totalOutputStreams - 1
		for _ in 0..<numBindPairs {
			_ = try reader.readMultiByteInteger()
			_ = try reader.readMultiByteInteger()
		}

		guard totalInputStreams >= numBindPairs else {
			throw SevenZipPreflightError.malformedHeader
		}
		let numPackedStreams = totalInputStreams - numBindPairs
		if numPackedStreams != 1 {
			for _ in 0..<numPackedStreams {
				_ = try reader.readMultiByteInteger()
			}
		}

		return try validatedMetadataCount(totalOutputStreams)
	}

	private func skipSubstreamInfo(
		reader: inout SevenZipMetadataReader,
		coderInfo: SevenZipCoderSummary
	) throws {
		var totalUnpackStreams = coderInfo.numFolders
		var unpackStreamsByFolder = Array(repeating: 1, count: coderInfo.numFolders)

		var type = try reader.readByte()
		if type == 0x0D {
			totalUnpackStreams = 0
			unpackStreamsByFolder.removeAll(keepingCapacity: true)
			for _ in 0..<coderInfo.numFolders {
				let numStreams = try validatedMetadataCount(reader.readMultiByteInteger())
				totalUnpackStreams = try validatedMetadataCount(
					checkedAdd(totalUnpackStreams, numStreams)
				)
				unpackStreamsByFolder.append(numStreams)
			}
			type = try reader.readByte()
		}

		if type == 0x09 {
			for numStreams in unpackStreamsByFolder where numStreams > 0 {
				for _ in 0..<(numStreams - 1) {
					_ = try reader.readMultiByteInteger()
				}
			}
			type = try reader.readByte()
		}

		if type == 0x0A {
			let definedCount = try reader.readDefinedBitCount(count: totalUnpackStreams)
			try reader.skipChecksums(count: definedCount)
			type = try reader.readByte()
		}

		guard type == 0x00 else {
			throw SevenZipPreflightError.malformedHeader
		}
	}

	private func validatedMetadataCount(_ count: @autoclosure () throws -> Int) throws -> Int {
		let value = try count()
		guard value <= maxEntryCount else {
			throw SevenZipPreviewError.metadataSizeLimitExceeded
		}
		return value
	}

	private func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
		let result = lhs.addingReportingOverflow(rhs)
		guard !result.overflow else {
			throw SevenZipPreviewError.metadataSizeLimitExceeded
		}
		return result.partialValue
	}

	private func littleEndianUInt64(at offset: Int) -> UInt64? {
		guard offset >= 0, offset <= data.count - 8 else {
			return nil
		}

		var value: UInt64 = 0
		for index in 0..<8 {
			value |= UInt64(data[offset + index]) << (8 * index)
		}
		return value
	}
}

private struct SevenZipCoderSummary {
	static let empty = SevenZipCoderSummary(numFolders: 0)

	let numFolders: Int
}

private struct SevenZipMetadataReader {
	private let data: Data
	private(set) var offset: Int
	private let endOffset: Int

	init(data: Data, offset: Int, endOffset: Int) {
		self.data = data
		self.offset = offset
		self.endOffset = endOffset
	}

	mutating func readByte() throws -> UInt8 {
		guard offset < endOffset, offset < data.count else {
			throw SevenZipPreflightError.malformedHeader
		}
		defer {
			offset += 1
		}
		return data[offset]
	}

	mutating func readMultiByteInteger() throws -> Int {
		let firstByte = try readByte()
		var mask: UInt8 = 0x80
		var value: UInt64 = 0

		for index in 0..<8 {
			if firstByte & mask == 0 {
				value |= UInt64(firstByte & (mask &- 1)) << (8 * index)
				return try checkedInt(value)
			}
			value |= UInt64(try readByte()) << (8 * index)
			mask >>= 1
		}

		return try checkedInt(value)
	}

	mutating func readDefinedBitCount(count: Int) throws -> Int {
		guard count >= 0 else {
			throw SevenZipPreflightError.malformedHeader
		}

		let allDefined = try readByte()
		if allDefined != 0 {
			return count
		}

		let byteCount = (count + 7) / 8
		var definedCount = 0
		for byteIndex in 0..<byteCount {
			let byte = try readByte()
			let bitsInByte = min(8, count - byteIndex * 8)
			for bitIndex in 0..<bitsInByte where byte & (UInt8(0x80) >> bitIndex) != 0 {
				definedCount += 1
			}
		}
		return definedCount
	}

	mutating func skip(_ count: Int) throws {
		guard count >= 0, count <= endOffset - offset else {
			throw SevenZipPreflightError.malformedHeader
		}
		offset += count
	}

	mutating func skipChecksums(count: Int) throws {
		for _ in 0..<count {
			try skip(4)
		}
	}

	private func checkedInt(_ value: UInt64) throws -> Int {
		guard value <= UInt64(Int.max) else {
			throw SevenZipPreviewError.metadataSizeLimitExceeded
		}
		return Int(value)
	}
}
