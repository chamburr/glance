import Foundation
import ZIPFoundation

class ZIPPreview: Preview {
	let filesRegex =
		#"(.{10}) +.+ +.+ +(\d+) +.+ +.+ +(\d{2}-\w{3}-\d{2} +\d{2}:\d{2}) +(.+)"#
	let sizeRegex = #"\d+ files?, (\d+) bytes? uncompressed, \d+ bytes? compressed: +([\d.]+)%"#

	let byteCountFormatter = ByteCountFormatter()
	let dateFormatter = DateFormatter()

	required init() {
		dateFormatter.locale = Locale(identifier: "en_US_POSIX")
		dateFormatter.dateFormat = "yy-MMM-dd HH:mm" // Date format used in `zipinfo` output
	}

	private func runZIPInfoCommand(filePath: String) throws -> String {
		let archiveURL = URL(fileURLWithPath: filePath)
		let archive = try Archive(url: archiveURL, accessMode: .read)

		var result = ""
		var entries = [String]()

		var fileCount = 0
		var uncompressed = 0
		var compressed = 0

		for entry in archive {
			var formatted = ""

			if entry.type == .directory {
				formatted += "drwxr-xr-x "
			} else {
				formatted += "-rw-r--r-- "
			}

			formatted += "2.0 unx "
			formatted += String(entry.uncompressedSize) + " "
			formatted += "bx stor "
			let modificationDate = entry.fileAttributes[.modificationDate] as? Date
				?? Date(timeIntervalSince1970: 0)
			formatted += dateFormatter
				.string(from: modificationDate) + " "
			formatted += entry.path

			entries.append(formatted)

			fileCount += 1
			uncompressed += Int(entry.uncompressedSize)
			compressed += Int(entry.compressedSize)
		}

		result += "Archive: archive.zip\n"
		result += "Zip file size: 0 bytes, number of entries: 0\n"
		if entries.isEmpty {
			result += "Empty zipfile."
			return result
		}

		result += entries.joined(separator: "\n") + "\n"
		result += String(fileCount) + " files, "
		result += String(uncompressed) + " bytes uncompressed, "
		result += String(compressed) + " bytes compressed: "
		if uncompressed == 0 {
			result += "0.0%"
		} else {
			result +=
				String(format: "%.1f%%", 100.0 - Double(compressed) / Double(uncompressed) * 100.0)
		}

		return result
	}

	/// Parses the output of the `zipinfo` command.
	private func parseZIPInfo(lines: String) -> (
		fileTree: FileTree,
		sizeUncompressed: Int?,
		compressionRatio: Double?
	) {
		let fileTree = FileTree()
		let linesSplit = lines.split(separator: "\n")

		// List entry format: "drwxr-xr-x  2.0 unx        0 bx stor 20-Jan-13 19:38 my-zip/dir/"
		// - Column 1: Permissions ("-" as first character indicates a file, "d" a directory)
		// - Column 4: File size in bytes
		// - Columns 7-8: Date modified
		// - Column 9: File path
		guard linesSplit.count >= 3 else {
			return (fileTree, 0, 0)
		}

		let filesString = linesSplit[2 ..< linesSplit.count - 1].joined(separator: "\n")
		let fileMatches = filesString.matchRegex(regex: filesRegex)
		for fileMatch in fileMatches {
			let permissions = fileMatch[1]
			let size = Int(fileMatch[2]) ?? 0
			let dateModified = dateFormatter.date(from: fileMatch[3])
			let path = fileMatch[4]
			// Ignore "__MACOSX" subdirectory (ZIP resource fork created by macOS)
			if !path.hasPrefix("__MACOSX") {
				do {
					// Add file/directory node to tree
					try fileTree.addNode(
						path: path,
						isDirectory: permissions.first == "d",
						size: size,
						dateModified: dateModified
					)
				} catch {
					Log.parse.error("\(error.localizedDescription, privacy: .public)")
				}
			}
		}

		// Last line:
		// - If not empty: "152 files, 192919 bytes uncompressed, 65061 bytes compressed:  66.3%"
		// - If empty: "Empty zipfile."
		if let lastLine = linesSplit.last, lastLine != "Empty zipfile." {
			let sizeMatches = String(lastLine).matchRegex(regex: sizeRegex)
			guard let sizeMatch = sizeMatches.first else {
				return (fileTree, nil, nil)
			}

			let sizeUncompressed = Int(sizeMatch[1])
			let compressionRatio = Double(sizeMatch[2])
			return (fileTree, sizeUncompressed, compressionRatio)
		} else {
			return (fileTree, 0, 0)
		}
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
		let zipInfoOutput = try runZIPInfoCommand(filePath: file.path)

		// Parse command output
		dateFormatter.timeZone = TimeZone.current
		let (fileTree, sizeUncompressed, compressionRatio) = parseZIPInfo(lines: zipInfoOutput)

		// Build label
		let compressionRatioText = compressionRatio.map { String($0) } ?? "--"
		let labelText = """
		Compressed: \(byteCountFormatter.string(for: file.size) ?? "--")
		Uncompressed: \(byteCountFormatter.string(for: sizeUncompressed) ?? "--")
		Compression ratio: \(compressionRatioText) %
		"""

		return OutlinePreviewVC(rootNodes: fileTree.root.childrenList, labelText: labelText)
	}
}
