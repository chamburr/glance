import Foundation
import os.log
import SWCompression

/// View controller for previewing tarballs (may be gzipped).
class TARPreview: Preview {
	let filesRegex = #"(.{10}) +\d+ +.+ +.+ +(\d+) +(\w{3} +\d+ +[\d:]+) +(.+)"#
	let sizeRegex = #" +\d+ +(\d+) +([\d.]+)% +.+"#

	let byteCountFormatter = ByteCountFormatter()
	let dateFormatter1 = DateFormatter()
	let dateFormatter2 = DateFormatter()

	required init() {
		initDateFormatters()
	}

	/// Sets up `dateFormatter1` and `dateFormatter2` to parse date strings from `tar` output. Date
	/// strings may be in one of the following formats:
	///
	/// - "MMM dd HH:mm", e.g. "Mar 28 15:36" (date is in current year)
	/// - "MMM dd  yyyy", e.g. "Dec 29  2018"
	private func initDateFormatters() {
		// Set default date to today to parse dates in current year
		dateFormatter1.defaultDate = Date()

		dateFormatter1.locale = Locale(identifier: "en_US_POSIX")
		dateFormatter2.locale = Locale(identifier: "en_US_POSIX")

		// Specify date formats
		dateFormatter1.dateFormat = "MMM dd HH:mm"
		dateFormatter2.dateFormat = "MMM dd  yyyy"
	}

	private func runTARFilesCommand(filePath: String) throws -> String {
		let archiveURL = URL(fileURLWithPath: filePath)
		let fileData = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
		let decompressedData = try? GzipArchive.unarchive(archive: fileData)
		let archive = try TarContainer.info(container: decompressedData ?? fileData)

		var entries = [String]()

		for entry in archive {
			var formatted = ""

			if entry.type == .directory {
				formatted += "drwxr-xr-x "
			} else {
				formatted += "-rw-r--r-- "
			}

			formatted += "0 user staff "
			formatted += String(entry.size ?? 0) + " "

			let modifiedYear = Calendar.current
				.component(.year, from: entry.modificationTime ?? Date())
			let currentYear = Calendar.current.component(.year, from: Date())

			if modifiedYear == currentYear {
				formatted += dateFormatter1.string(from: entry.modificationTime ?? Date()) + " "
			} else {
				formatted += dateFormatter2.string(from: entry.modificationTime ?? Date()) + " "
			}

			formatted += entry.name

			entries.append(formatted)
		}

		return entries.joined(separator: "\n")
	}

	private func runGZIPSizeCommand(filePath: String) throws -> String {
		let archiveURL = URL(fileURLWithPath: filePath)
		let fileData = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
		let decompressedData = try? GzipArchive.unarchive(archive: fileData)

		let compressed = fileData.count
		let uncompressed = decompressedData?.count ?? 0

		var result =
			" compressed uncompressed ratio uncompressed_name\n \(compressed) \(uncompressed) "

		if uncompressed == 0 {
			result += "0.0% "
		} else {
			result +=
				String(format: "%.1f%% ", 100.0 - Double(compressed) / Double(uncompressed) * 100.0)
		}

		result += "archive.tar "
		return result
	}

	/// Parses a date string from `tar` output to a `Date` object.
	private func parseDate(dateString: String) -> Date? {
		if dateString.contains(":") {
			return dateFormatter1.date(from: dateString)
		} else {
			return dateFormatter2.date(from: dateString)
		}
	}

	private func parseTARFiles(lines: String) -> FileTree {
		let fileTree = FileTree()

		// List entry format: "-rw-r--r--  0 user staff     642 Dec 29  2018 my-tar/file.ext"
		// - Column 1: Permissions ("-" as first character indicates a file, "d" a directory)
		// - Column 5: File size in bytes
		// - Columns 6-8: Date modified
		// - Column 9: File path
		let fileMatches = lines.matchRegex(regex: filesRegex)
		for fileMatch in fileMatches {
			let permissions = fileMatch[1]
			let size = Int(fileMatch[2]) ?? 0
			let dateModified = parseDate(dateString: fileMatch[3])
			let path = fileMatch[4]
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

		return fileTree
	}

	private func parseGZIPSize(lines: String)
		-> (sizeUncompressed: Int?, compressionRatio: Double?)
	{
		let sizeMatches = lines.matchRegex(regex: sizeRegex)
		let sizeUncompressed = Int(sizeMatches[0][1])
		let compressionRatio = Double(sizeMatches[0][2])
		return (sizeUncompressed, compressionRatio)
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		let isGzipped = file.path.hasSuffix(".tar.gz") || file.path.hasSuffix(".tgz")

		// Parse TAR contents
		let filesOutput = try runTARFilesCommand(filePath: file.path)
		let fileTree = parseTARFiles(lines: filesOutput)
		var labelText =
			"\(isGzipped ? "Compressed" : "Size"): \(byteCountFormatter.string(for: file.size) ?? "--")"

		// If tarball is gzipped: Get compression information
		if isGzipped {
			let sizeOutput = try runGZIPSizeCommand(filePath: file.path)
			let (sizeUncompressed, compressionRatio) = parseGZIPSize(lines: sizeOutput)
			labelText += """

			Uncompressed: \(byteCountFormatter.string(for: sizeUncompressed) ?? "--")
			Compression ratio: \(compressionRatio == nil ? "--" : String(compressionRatio!)) %
			"""
		}

		return OutlinePreviewVC(rootNodes: fileTree.root.childrenList, labelText: labelText)
	}
}
