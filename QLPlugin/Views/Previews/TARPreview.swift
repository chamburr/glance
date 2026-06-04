import Foundation
import zlib

/// View controller for previewing tarballs (may be gzipped).
class TARPreview: Preview {
	let byteCountFormatter = ByteCountFormatter()
	private let maxEntryCount = 50_000
	private let maxMetadataEntrySize: Int64 = 1_048_576
	private let maxGzippedUncompressedScanSize: Int64 = 200 * 1_024 * 1_024

	required init() {}

	private func scanArchive(file: File, isGzipped: Bool) throws -> TarScanResult {
		let reader: TarByteReader = try {
			if isGzipped {
				return try GzipTarByteReader(url: file.url)
			}
			return try FileTarByteReader(url: file.url, fileSize: Int64(file.size))
		}()
		defer {
			try? reader.close()
		}

		let scanner = TarHeaderScanner(
			reader: reader,
			maxEntryCount: maxEntryCount,
			maxMetadataEntrySize: maxMetadataEntrySize,
			maxGzippedUncompressedScanSize: maxGzippedUncompressedScanSize,
			shouldLimitPayloadSkips: isGzipped
		)
		let result = try scanner.scan()
		try reader.close()
		return result
	}

	private func compressionRatioText(compressed: Int64, uncompressed: Int64) -> String {
		if uncompressed == 0 {
			return "0.0"
		}
		let ratio = 100.0 - Double(compressed) / Double(uncompressed) * 100.0
		return String(format: "%.1f", ratio)
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		let normalizedPath = file.path.lowercased()
		let isGzipped = normalizedPath.hasSuffix(".tar.gz") || normalizedPath.hasSuffix(".tgz")

		let scanResult = try scanArchive(file: file, isGzipped: isGzipped)
		var labelText =
			"\(isGzipped ? "Compressed" : "Size"): \(byteCountFormatter.string(fromByteCount: Int64(file.size)))"

		if isGzipped {
			let uncompressedPrefix = scanResult.isTruncated ? "at least " : ""
			labelText += """

			Uncompressed: \(uncompressedPrefix)\(byteCountFormatter.string(fromByteCount: scanResult.uncompressedByteCount))
			"""
			if scanResult.isTruncated {
				labelText += "\nPreview truncated after scanning \(byteCountFormatter.string(fromByteCount: scanResult.uncompressedByteCount))"
			} else {
				labelText += "\nCompression ratio: \(compressionRatioText(compressed: Int64(file.size), uncompressed: scanResult.uncompressedByteCount)) %"
			}
		} else if scanResult.isTruncated {
			labelText += "\nPreview truncated after \(maxEntryCount) entries"
		}

		return OutlinePreviewVC(rootNodes: scanResult.fileTree.root.childrenList, labelText: labelText)
	}
}

private struct TarScanResult {
	let fileTree: FileTree
	let uncompressedByteCount: Int64
	let isTruncated: Bool
}

private enum TARPreviewError: LocalizedError {
	case truncatedArchive
	case invalidHeader
	case gzipOpenFailed(path: String)
	case gzipReadFailed(path: String, message: String)

	var errorDescription: String? {
		switch self {
			case .truncatedArchive:
				"TAR archive is truncated"
			case .invalidHeader:
				"TAR archive has an invalid header"
			case let .gzipOpenFailed(path):
				"Could not open gzipped TAR archive \(path)"
			case let .gzipReadFailed(path, message):
				"Could not read gzipped TAR archive \(path): \(message)"
		}
	}
}

private protocol TarByteReader: AnyObject {
	func read(upToCount count: Int) throws -> Data
	func skip(count: Int64) throws
	func close() throws
}

private final class FileTarByteReader: TarByteReader {
	private let handle: FileHandle
	private let fileSize: Int64
	private var isClosed = false

	init(url: URL, fileSize: Int64) throws {
		handle = try FileHandle(forReadingFrom: url)
		self.fileSize = fileSize
	}

	func read(upToCount count: Int) throws -> Data {
		try handle.read(upToCount: count) ?? Data()
	}

	func skip(count: Int64) throws {
		guard count >= 0 else {
			throw TARPreviewError.invalidHeader
		}

		let currentOffset = Int64(try handle.offset())
		let targetOffset = currentOffset + count
		guard targetOffset >= currentOffset, targetOffset <= fileSize else {
			throw TARPreviewError.truncatedArchive
		}
		try handle.seek(toOffset: UInt64(targetOffset))
	}

	func close() throws {
		guard !isClosed else {
			return
		}
		isClosed = true
		try handle.close()
	}

	deinit {
		try? close()
	}
}

private final class GzipTarByteReader: TarByteReader {
	private let path: String
	private var gzipFile: gzFile?

	init(url: URL) throws {
		path = url.path
		gzipFile = gzopen(path, "rb")
		guard gzipFile != nil else {
			throw TARPreviewError.gzipOpenFailed(path: path)
		}
	}

	func read(upToCount count: Int) throws -> Data {
		guard let gzipFile else {
			return Data()
		}

		var data = Data(count: count)
		let readCount = data.withUnsafeMutableBytes { bytes in
			gzread(gzipFile, bytes.baseAddress, UInt32(count))
		}
		guard readCount >= 0 else {
			throw TARPreviewError.gzipReadFailed(path: path, message: gzipErrorMessage())
		}

		data.removeSubrange(Int(readCount)..<data.count)
		return data
	}

	func skip(count: Int64) throws {
		guard count >= 0 else {
			throw TARPreviewError.invalidHeader
		}

		var remaining = count
		while remaining > 0 {
			let chunkSize = Int(min(remaining, 64 * 1_024))
			let data = try read(upToCount: chunkSize)
			guard !data.isEmpty else {
				throw TARPreviewError.truncatedArchive
			}
			remaining -= Int64(data.count)
		}
	}

	func close() throws {
		guard let gzipFile else {
			return
		}
		self.gzipFile = nil
		let result = gzclose(gzipFile)
		guard result == Z_OK else {
			throw TARPreviewError.gzipReadFailed(path: path, message: "zlib close failed with status \(result)")
		}
	}

	private func gzipErrorMessage() -> String {
		guard let gzipFile else {
			return "gzip stream is closed"
		}
		var errorNumber: Int32 = 0
		guard let message = gzerror(gzipFile, &errorNumber) else {
			return "unknown gzip error"
		}
		return String(cString: message)
	}

	deinit {
		try? close()
	}
}

private final class TarHeaderScanner {
	private let reader: TarByteReader
	private let maxEntryCount: Int
	private let maxMetadataEntrySize: Int64
	private let maxGzippedUncompressedScanSize: Int64
	private let shouldLimitPayloadSkips: Bool
	private let fileTree = FileTree()
	private var uncompressedByteCount: Int64 = 0
	private var entryCount = 0
	private var isTruncated = false
	private var pendingLongName: String?
	private var pendingLocalPAX = TarPAXHeaders()
	private var globalPAX = TarPAXHeaders()

	init(
		reader: TarByteReader,
		maxEntryCount: Int,
		maxMetadataEntrySize: Int64,
		maxGzippedUncompressedScanSize: Int64,
		shouldLimitPayloadSkips: Bool
	) {
		self.reader = reader
		self.maxEntryCount = maxEntryCount
		self.maxMetadataEntrySize = maxMetadataEntrySize
		self.maxGzippedUncompressedScanSize = maxGzippedUncompressedScanSize
		self.shouldLimitPayloadSkips = shouldLimitPayloadSkips
	}

	func scan() throws -> TarScanResult {
		scanLoop: while true {
			let headerData = try readExactly(512, allowEmptyAtEOF: true)
			if headerData.isEmpty {
				break
			}
			try addScannedBytes(512)

			if headerData.isZeroTarBlock {
				let endMarkerData = try readExactly(512, allowEmptyAtEOF: true)
				if !endMarkerData.isEmpty {
					try addScannedBytes(512)
				}
				break
			}

			let header = try TarHeader(data: headerData)
			let payloadSize = header.entryType.usesPAXSizeOverride
				? pendingLocalPAX.size ?? globalPAX.size ?? header.size
				: header.size
			let paddedPayloadSize = try paddedTarSize(payloadSize)

			switch header.entryType {
				case .globalPAX:
					if try shouldStopBeforeSkipping(paddedPayloadSize) {
						break scanLoop
					}
					if let payload = try readMetadataPayload(size: payloadSize, paddedSize: paddedPayloadSize) {
						globalPAX = TarPAXHeaders(data: payload)
					}
				case .localPAX:
					if try shouldStopBeforeSkipping(paddedPayloadSize) {
						break scanLoop
					}
					if let payload = try readMetadataPayload(size: payloadSize, paddedSize: paddedPayloadSize) {
						pendingLocalPAX = TarPAXHeaders(data: payload)
					}
				case .longName:
					if try shouldStopBeforeSkipping(paddedPayloadSize) {
						break scanLoop
					}
					pendingLongName = try readMetadataPayload(size: payloadSize, paddedSize: paddedPayloadSize)
						.flatMap(Self.stringFromMetadataPayload)
				case .longLinkName:
					if try shouldStopBeforeSkipping(paddedPayloadSize) {
						break scanLoop
					}
					try reader.skip(count: paddedPayloadSize)
					try addScannedBytes(paddedPayloadSize)
				case .file, .directory, .other:
					try addEntry(from: header, payloadSize: payloadSize)
					if isTruncated {
						break scanLoop
					}
					if try shouldStopBeforeSkipping(paddedPayloadSize) {
						break scanLoop
					}
					try reader.skip(count: paddedPayloadSize)
					try addScannedBytes(paddedPayloadSize)
					pendingLongName = nil
					pendingLocalPAX = TarPAXHeaders()
			}
		}

		return TarScanResult(
			fileTree: fileTree,
			uncompressedByteCount: uncompressedByteCount,
			isTruncated: isTruncated
		)
	}

	private func addEntry(from header: TarHeader, payloadSize: Int64) throws {
		guard entryCount < maxEntryCount else {
			isTruncated = true
			return
		}

		entryCount += 1
		let path = pendingLocalPAX.path ?? pendingLongName ?? globalPAX.path ?? header.path
		guard !path.isEmpty else {
			return
		}

		let isDirectory = header.entryType == .directory || path.hasSuffix("/")
		do {
			try fileTree.addNode(
				path: path,
				isDirectory: isDirectory,
				size: isDirectory ? 0 : clampedSize(payloadSize),
				dateModified: pendingLocalPAX.modificationTime ?? globalPAX.modificationTime ?? header.modificationTime
			)
		} catch {
			Log.parse.error("\(error.localizedDescription, privacy: .private)")
		}
	}

	private func readMetadataPayload(size: Int64, paddedSize: Int64) throws -> Data? {
		guard size <= maxMetadataEntrySize else {
			try reader.skip(count: paddedSize)
			try addScannedBytes(paddedSize)
			return nil
		}

		let payload = try readExactly(Int(size), allowEmptyAtEOF: false)
		try reader.skip(count: paddedSize - size)
		try addScannedBytes(paddedSize)
		return payload
	}

	private func readExactly(_ count: Int, allowEmptyAtEOF: Bool) throws -> Data {
		var result = Data()
		while result.count < count {
			let chunk = try reader.read(upToCount: count - result.count)
			if chunk.isEmpty {
				if allowEmptyAtEOF, result.isEmpty {
					return Data()
				}
				throw TARPreviewError.truncatedArchive
			}
			result.append(chunk)
		}
		return result
	}

	private func shouldStopBeforeSkipping(_ paddedPayloadSize: Int64) throws -> Bool {
		guard shouldLimitPayloadSkips else {
			return false
		}
		guard uncompressedByteCount + paddedPayloadSize <= maxGzippedUncompressedScanSize else {
			isTruncated = true
			return true
		}
		return false
	}

	private func addScannedBytes(_ count: Int64) throws {
		guard count >= 0, uncompressedByteCount <= Int64.max - count else {
			throw TARPreviewError.invalidHeader
		}
		uncompressedByteCount += count
	}

	private func paddedTarSize(_ size: Int64) throws -> Int64 {
		guard size >= 0, size <= Int64.max - 511 else {
			throw TARPreviewError.invalidHeader
		}
		let remainder = size % 512
		return remainder == 0 ? size : size + 512 - remainder
	}

	private func clampedSize(_ size: Int64) -> Int {
		if size > Int64(Int.max) {
			return Int.max
		}
		return Int(size)
	}

	private static func stringFromMetadataPayload(_ data: Data) -> String {
		let string = String(decoding: data, as: UTF8.self)
		return string.split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false)
			.first
			.map(String.init) ?? ""
	}
}

private struct TarHeader {
	let path: String
	let size: Int64
	let modificationTime: Date?
	let entryType: TarEntryType

	init(data: Data) throws {
		guard data.count == 512, !data.isZeroTarBlock else {
			throw TARPreviewError.invalidHeader
		}

		let storedChecksum = try data.tarOctalInteger(in: 148..<156)
		let computedChecksum = data.tarChecksum()
		guard storedChecksum == 0 || storedChecksum == computedChecksum else {
			throw TARPreviewError.invalidHeader
		}

		let name = data.tarString(in: 0..<100)
		let prefix = data.tarString(in: 345..<500)
		path = prefix.isEmpty ? name : "\(prefix)/\(name)"
		size = try data.tarOctalInteger(in: 124..<136)

		let modificationTimestamp = try data.tarOctalInteger(in: 136..<148)
		modificationTime = modificationTimestamp > 0
			? Date(timeIntervalSince1970: TimeInterval(modificationTimestamp))
			: nil
		entryType = TarEntryType(typeFlag: data[156])
	}
}

private enum TarEntryType {
	case file
	case directory
	case globalPAX
	case localPAX
	case longName
	case longLinkName
	case other

	init(typeFlag: UInt8) {
		switch typeFlag {
			case 0, UInt8(ascii: "0"):
				self = .file
			case UInt8(ascii: "5"):
				self = .directory
			case UInt8(ascii: "g"):
				self = .globalPAX
			case UInt8(ascii: "x"):
				self = .localPAX
			case UInt8(ascii: "L"):
				self = .longName
			case UInt8(ascii: "K"):
				self = .longLinkName
			default:
				self = .other
		}
	}

	var usesPAXSizeOverride: Bool {
		switch self {
			case .file, .directory, .other:
				true
			case .globalPAX, .localPAX, .longName, .longLinkName:
				false
		}
	}
}

private struct TarPAXHeaders {
	let path: String?
	let size: Int64?
	let modificationTime: Date?

	init(path: String? = nil, size: Int64? = nil, modificationTime: Date? = nil) {
		self.path = path
		self.size = size
		self.modificationTime = modificationTime
	}

	init(data: Data) {
		var values = [String: String]()
		let bytes = Array(data)
		var offset = 0

		while offset < bytes.count {
			guard let spaceIndex = bytes[offset...].firstIndex(of: UInt8(ascii: " ")) else {
				break
			}
			let lengthText = String(decoding: bytes[offset..<spaceIndex], as: UTF8.self)
			guard let length = Int(lengthText), length > 0 else {
				break
			}
			let recordEnd = offset + length
			guard recordEnd <= bytes.count, spaceIndex + 1 < recordEnd else {
				break
			}

			let recordBytes = bytes[(spaceIndex + 1)..<recordEnd].dropLast()
			if let equalsIndex = recordBytes.firstIndex(of: UInt8(ascii: "=")) {
				let key = String(decoding: recordBytes[..<equalsIndex], as: UTF8.self)
				let value = String(decoding: recordBytes[(equalsIndex + 1)...], as: UTF8.self)
				values[key] = value
			}
			offset = recordEnd
		}

		path = values["path"]
		size = values["size"].flatMap(Int64.init)
		modificationTime = values["mtime"]
			.flatMap(Double.init)
			.map { Date(timeIntervalSince1970: $0) }
	}
}

private extension Data {
	var isZeroTarBlock: Bool {
		count == 512 && allSatisfy { $0 == 0 }
	}

	func tarString(in range: Range<Int>) -> String {
		let bytes = Array(self[range])
		let endIndex = bytes.firstIndex(of: 0) ?? bytes.count
		return String(decoding: bytes[..<endIndex], as: UTF8.self)
	}

	func tarOctalInteger(in range: Range<Int>) throws -> Int64 {
		let bytes = Array(self[range])
		if let firstByte = bytes.first, firstByte & 0x80 != 0 {
			return try tarBase256Integer(bytes: bytes)
		}

		let text = String(
			decoding: bytes.filter { $0 != 0 && $0 != UInt8(ascii: " ") },
			as: UTF8.self
		)
		guard !text.isEmpty else {
			return 0
		}
		guard let value = Int64(text, radix: 8) else {
			throw TARPreviewError.invalidHeader
		}
		return value
	}

	func tarChecksum() -> Int64 {
		enumerated().reduce(0) { partialResult, byte in
			partialResult + Int64(byte.offset >= 148 && byte.offset < 156 ? UInt8(ascii: " ") : byte.element)
		}
	}

	private func tarBase256Integer(bytes: [UInt8]) throws -> Int64 {
		var bytes = bytes
		bytes[0] &= 0x7f

		var value: Int64 = 0
		for byte in bytes {
			guard value <= (Int64.max - Int64(byte)) / 256 else {
				throw TARPreviewError.invalidHeader
			}
			value = value * 256 + Int64(byte)
		}
		return value
	}
}
