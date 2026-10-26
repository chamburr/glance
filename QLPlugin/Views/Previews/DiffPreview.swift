// swiftformat:disable wrapMultilineStatementBraces
import Foundation

class DiffPreview: Preview {
	private struct DiffFile {
		var name: String
		var rows: [String] = []
	}

	private static let maxSourceBytes = 16_000_000
	private static let maxFiles = 200
	// swiftformat:disable:next numberFormatting
	private static let maxRows = 12_000
	private static let maxLineLength = 2000
	private static let maxHTMLBytes = 4_000_000

	private static func escapedHTML(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}

	required init() {}

	func createPreviewVC(file: File) throws -> PreviewVC {
		guard file.size <= Self.maxSourceBytes else {
			return WebPreviewVC(html: "<p>Patch exceeds the 16 MB preview limit.</p>")
		}
		let source = try file.read()
		return WebPreviewVC(html: Self.renderHTML(source: source))
	}

	/// Kept separate from file I/O so patch fixtures can exercise rendering directly.
	static func renderHTML(source: String) -> String {
		guard source.utf8.count <= maxSourceBytes else {
			return "<p>Patch exceeds the 16 MB preview limit.</p>"
		}
		var files: [DiffFile] = []
		var current = DiffFile(name: "Patch")
		var oldLine: Int?
		var newLine: Int?
		var oldRemaining = 0
		var newRemaining = 0
		var inHunk = false
		var hasHunk = false
		var rows = 0
		var htmlBytes = 0
		var limited = false

		func append(_ line: String, kind: String, old: Int? = nil, new: Int? = nil) {
			guard !limited else {
				return
			}
			let display = String(line.prefix(maxLineLength))
			let suffix = line.count > maxLineLength ? "…" : ""
			let row = "<div class=\"diff-row \(kind)\"><span class=\"diff-number\">\(old.map(String.init) ?? "")</span><span class=\"diff-number\">\(new.map(String.init) ?? "")</span><span class=\"diff-text\">\(escapedHTML(display + suffix))</span></div>"
			guard rows < maxRows, htmlBytes + row.utf8.count <= maxHTMLBytes else {
				limited = true
				return
			}
			current.rows.append(row)
			rows += 1
			htmlBytes += row.utf8.count
		}

		func finishFile() {
			if !current.rows.isEmpty { files.append(current) }
			current = DiffFile(name: "Patch")
			inHunk = false
			hasHunk = false
		}

		for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
			if limited { break }
			let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : String(rawLine)
			if line.hasPrefix("diff --git ") {
				if !current.rows.isEmpty { finishFile() }
				if files.count >= maxFiles { limited = true; break }
				current.name = line.components(separatedBy: " b/").last ?? "Patch"
				append(line, kind: "diff-header")
				continue
			}
			if line.hasPrefix("--- "), !inHunk || oldRemaining == 0 && newRemaining == 0 {
				if hasHunk {
					finishFile()
					if files.count >= maxFiles { limited = true; break }
				}
				append(line, kind: "diff-meta")
				continue
			}
			if line.hasPrefix("+++ "), !inHunk || oldRemaining == 0 && newRemaining == 0 {
				let path = String(line.dropFirst(4)).components(separatedBy: "\t")[0]
				if path != "/dev/null" {
					current.name = path.hasPrefix("b/") ? String(path.dropFirst(2)) : path
				}
				append(line, kind: "diff-meta")
				continue
			}
			if let ranges = hunkRanges(line) {
				oldLine = ranges.oldStart
				newLine = ranges.newStart
				oldRemaining = ranges.oldCount
				newRemaining = ranges.newCount
				inHunk = true
				hasHunk = true
				append(line, kind: "diff-hunk")
				continue
			}
			if line.hasPrefix("@@@") {
				// Combined diffs have multiple old-side columns. Preserve them without false line
				// numbers.
				inHunk = false
				hasHunk = true
				append(line, kind: "diff-hunk")
				continue
			}
			if line.hasPrefix("@@") {
				// A malformed hunk cannot inherit line numbers from the previous one.
				inHunk = false
				append(line, kind: "diff-meta")
				continue
			}
			if line.hasPrefix("\\ No newline at end of file") {
				append(line, kind: "diff-meta")
				continue
			}
			if inHunk, let old = oldLine, let new = newLine {
				if line.hasPrefix("+"), newRemaining > 0 {
					append(line, kind: "diff-add", new: new)
					newLine = new + 1
					newRemaining -= 1
					continue
				}
				if line.hasPrefix("-"), oldRemaining > 0 {
					append(line, kind: "diff-remove", old: old)
					oldLine = old + 1
					oldRemaining -= 1
					continue
				}
				if line.hasPrefix(" "), oldRemaining > 0, newRemaining > 0 {
					append(line, kind: "diff-context", old: old, new: new)
					oldLine = old + 1
					newLine = new + 1
					oldRemaining -= 1
					newRemaining -= 1
					continue
				}
			}
			append(line, kind: "diff-meta")
		}
		if !current.rows.isEmpty { files.append(current) }
		if files.isEmpty { files.append(DiffFile(name: "Patch", rows: [])) }

		var html = """
		<style>
		.diff-files { display:flex; gap:6px; overflow-x:auto; padding:8px 0; margin-bottom:12px; }
		.diff-files a { flex:none; padding:5px 9px; border:1px solid var(--color-border); border-radius:5px; text-decoration:none; }
		.diff-file { margin:0 0 24px; scroll-margin-top:10px; }
		.diff-file h2 { overflow-wrap:anywhere; font-size:1.05em; }
		.diff-code { overflow:auto; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:.9em; }
		.diff-row { display:grid; grid-template-columns:4.5em 4.5em minmax(max-content,1fr); min-height:1.45em; white-space:pre; }
		.diff-number { padding-right:.7em; text-align:right; color:#777; user-select:none; border-right:1px solid var(--color-border); }
		.diff-text { padding:0 .7em; }
		.diff-add { background:rgba(35,160,75,.16); }
		.diff-remove { background:rgba(210,60,60,.16); }
		.diff-hunk { background:rgba(80,125,205,.16); color:#4774b7; }
		.diff-header { font-weight:bold; }
		.diff-meta { color:#777; }
		body.wrap .diff-row { white-space:pre-wrap; overflow-wrap:anywhere; }
		</style>
		"""
		if files.count > 1 {
			html += "<nav class=\"diff-files\" aria-label=\"Changed files\">"
			for (index, file) in files.enumerated() {
				html += "<a href=\"#diff-file-\(index)\">\(escapedHTML(file.name))</a>"
			}
			html += "</nav>"
		}
		for (index, file) in files.enumerated() {
			html += "<section class=\"diff-file\" id=\"diff-file-\(index)\"><h2>\(escapedHTML(file.name))</h2><div class=\"diff-code\">"
			html += file.rows.joined()
			html += "</div></section>"
		}
		if limited {
			html +=
				"<p>Preview limit reached. Open the original file to read the complete patch.</p>"
		}
		return html
	}

	private static func hunkRanges(_ line: String) -> (
		oldStart: Int, oldCount: Int, newStart: Int, newCount: Int
	)? {
		guard line.hasPrefix("@@ "),
		      let match = line.matchRegex(regex: "^@@ -(\\d+)(?:,(\\d+))? \\+(\\d+)(?:,(\\d+))? @@")
		      .first,
		      match.count == 5,
		      let oldStart = Int(match[1]),
		      let newStart = Int(match[3]),
		      let oldCount = Int(match[2].isEmpty ? "1" : match[2]),
		      let newCount = Int(match[4].isEmpty ? "1" : match[4]),
		      oldStart <= Int.max - maxRows,
		      newStart <= Int.max - maxRows
		else { return nil }
		return (oldStart, oldCount, newStart, newCount)
	}
}
