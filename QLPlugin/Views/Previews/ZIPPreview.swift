import Foundation
import os.log
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
		guard let archive = Archive(url: archiveURL, accessMode: .read) else {
			return ""
		}

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
			formatted += dateFormatter
				.string(from: entry.fileAttributes[.modificationDate] as! Date) + " "
			formatted += entry.path

			entries.append(formatted)

			fileCount += 1
			uncompressed += entry.uncompressedSize
			compressed += entry.compressedSize
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
					os_log("%{public}s", log: Log.parse, type: .error, error.localizedDescription)
				}
			}
		}

		// Last line:
		// - If not empty: "152 files, 192919 bytes uncompressed, 65061 bytes compressed:  66.3%"
		// - If empty: "Empty zipfile."
		if let lastLine = linesSplit.last, lastLine != "Empty zipfile." {
			let sizeMatches = String(lastLine).matchRegex(regex: sizeRegex)
			let sizeUncompressed = Int(sizeMatches[0][1])
			let compressionRatio = Double(sizeMatches[0][2])
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
		let labelText = """
		Compressed: \(byteCountFormatter.string(for: file.size) ?? "--")
		Uncompressed: \(byteCountFormatter.string(for: sizeUncompressed) ?? "--")
		Compression ratio: \(compressionRatio == nil ? "--" : String(compressionRatio!)) %
		"""

		return OutlinePreviewVC(rootNodes: fileTree.root.childrenList, labelText: labelText)
	}
}
