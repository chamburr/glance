// swiftformat:disable wrapMultilineStatementBraces
import Cocoa
import SQLite3

func escapedHTML(_ text: String) -> String {
	text.replacingOccurrences(of: "&", with: "&amp;")
		.replacingOccurrences(of: "<", with: "&lt;")
		.replacingOccurrences(of: ">", with: "&gt;")
		.replacingOccurrences(of: "\"", with: "&quot;")
}

/// Directory traversal is bounded, never follows symbolic links, and never enters app packages.
class FolderPreview: Preview {
	required init() {}

	func createPreviewVC(file: File) throws -> PreviewVC {
		var remaining = 2000
		func list(_ directory: URL, depth: Int) throws -> String {
			guard depth < 4, remaining > 0 else {
				return "<p>Preview limit reached.</p>"
			}
			let keys: Set<URLResourceKey> = [
				.isDirectoryKey,
				.isSymbolicLinkKey,
				.isPackageKey,
				.fileSizeKey,
			]
			guard let entries = FileManager.default.enumerator(
				at: directory,
				includingPropertiesForKeys: Array(keys),
				options: [
					.skipsHiddenFiles,
					.skipsSubdirectoryDescendants,
					.skipsPackageDescendants,
				]
			) else {
				throw FileError.fileReadError(
					path: directory.path,
					message: "Cannot enumerate folder"
				)
			}
			let children = entries.prefix(remaining + 1).compactMap { $0 as? URL }.sorted {
				$0.lastPathComponent
					.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
			}
			var result = "<ul>"
			for child in children {
				guard remaining > 0
				else { result += "<li>Preview limited to 2,000 entries.</li>"; break }
				remaining -= 1
				let values = try child.resourceValues(forKeys: keys)
				let name = escapedHTML(child.lastPathComponent)
				if values.isDirectory == true, values.isSymbolicLink != true,
				   values.isPackage != true {
					result += "<li><details><summary>📁 \(name)</summary>"
					result += (try? list(
						child,
						depth: depth + 1
					)) ?? "<p>Folder is not readable.</p>"
					result += "</details></li>"
				} else {
					let size = ByteCountFormatter.string(
						fromByteCount: Int64(values.fileSize ?? 0),
						countStyle: .file
					)
					result += "<li>\(name) <small>\(size)</small></li>"
				}
			}
			return result + "</ul>"
		}
		return WebPreviewVC(html: "<h1>\(escapedHTML(file.url.lastPathComponent))</h1>" + (try list(
			file.url,
			depth: 0
		)))
	}
}

/// SQLite is opened read-only. Only ordinary tables are selected; no user SQL or extensions run.
class DatabasePreview: Preview {
	required init() {}

	func createPreviewVC(file: File) throws -> PreviewVC {
		var database: OpaquePointer?
		guard sqlite3_open_v2(
			file.path,
			&database,
			SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
			nil
		) == SQLITE_OK,
			let connection = database
		else {
			if database != nil {
				sqlite3_close(database)
			}
			throw FileError.fileReadError(
				path: file.path,
				message: "Not a readable SQLite database"
			)
		}
		defer { sqlite3_close(connection) }
		sqlite3_busy_timeout(connection, 200)
		sqlite3_limit(connection, SQLITE_LIMIT_LENGTH, 1_000_000)
		sqlite3_limit(connection, SQLITE_LIMIT_COLUMN, 200)
		sqlite3_exec(connection, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF", nil, nil, nil)
		let deadline = Date().addingTimeInterval(2)
		let deadlinePointer = UnsafeMutablePointer<Date>.allocate(capacity: 1)
		deadlinePointer.initialize(to: deadline)
		defer { deadlinePointer.deinitialize(count: 1); deadlinePointer.deallocate() }
		sqlite3_progress_handler(
			connection,
			1000,
			{ context in
				guard let context = context else {
					return 1
				}
				return Date() > context.assumingMemoryBound(to: Date.self).pointee ? 1 : 0
			},
			deadlinePointer
		)
		var statement: OpaquePointer?
		let sql = "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND upper(sql) NOT LIKE 'CREATE VIRTUAL%' ORDER BY name LIMIT 50"
		guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
			throw FileError.fileReadError(path: file.path, message: "Cannot read SQLite schema")
		}
		defer { sqlite3_finalize(statement) }
		var names: [String] = []
		while sqlite3_step(statement) == SQLITE_ROW {
			if let text = sqlite3_column_text(statement, 0) {
				names.append(String(cString: text))
			}
		}
		var html = "<h1>\(escapedHTML(file.url.lastPathComponent))</h1><p>Read-only · first 200 rows per table · at most 50 tables. Pages browse only these preview rows.</p>"
		html += "<label>Table <select id=\"glance-database-table\"><option value=\"all\">All tables</option>"
		for (index, name) in names.enumerated() {
			html += "<option value=\"\(index)\">\(escapedHTML(name))</option>"
		}
		html += "</select></label>"
		for (tableIndex, name) in names.enumerated() {
			if Date() > deadline || html.utf8.count > 2_000_000 { break }
			let quoted = "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
			var rows: OpaquePointer?
			guard sqlite3_prepare_v2(
				connection,
				"SELECT * FROM \(quoted) LIMIT 201",
				-1,
				&rows,
				nil
			) == SQLITE_OK else { continue }
			defer { sqlite3_finalize(rows) }
			html += "<details class=\"glance-database\" data-table=\"\(tableIndex)\"><summary>\(escapedHTML(name))</summary><div style=\"overflow:auto\"><table><thead><tr>"
			let columns = sqlite3_column_count(rows)
			for index in 0 ..<
				columns {
				let declaredType = sqlite3_column_decltype(rows, index)
					.map { String(cString: $0) } ?? "Undeclared type"
				html += "<th title=\"\(escapedHTML(declaredType))\">\(escapedHTML(String(cString: sqlite3_column_name(rows, index))))</th>"
			}
			html += "</tr></thead><tbody>"
			var count = 0
			while sqlite3_step(rows) == SQLITE_ROW {
				if Date() > deadline || html.utf8.count > 2_000_000 { break }
				guard count < 200
				else { break }
				count += 1
				html += "<tr>"
				for index in 0 ..< columns {
					let value: String
					if sqlite3_column_type(rows, index) ==
						SQLITE_BLOB {
						value = "[BLOB: \(sqlite3_column_bytes(rows, index)) bytes]"
					} else if let text = sqlite3_column_text(rows, index) {
						value = String(String(cString: text).prefix(2000))
					} else {
						value = "NULL"
					}
					html += "<td>\(escapedHTML(value))</td>"
				}
				html += "</tr>"
			}
			html += "</tbody></table></div><div class=\"glance-database-pages\"></div>"
			if count ==
				200 { html += "<p>Preview capped at 200 rows; additional rows may be omitted.</p>" }
			html += "</details>"
		}
		if Date() > deadline {
			html += "<p>Preview time limit reached.</p>"
		}
		return WebPreviewVC(html: html, scripts: [Script(content: Self.navigationScript)])
	}

	private static let navigationScript = """
	const tables = Array.from(document.querySelectorAll('.glance-database'));
	for (const section of tables) {
	  const rows = Array.from(section.querySelectorAll('tbody tr'));
	  let page = 0;
	  const pages = Math.max(1, Math.ceil(rows.length / 50));
	  const controls = section.querySelector('.glance-database-pages');
	  const previous = document.createElement('button'); previous.textContent = 'Previous';
	  const next = document.createElement('button'); next.textContent = 'Next';
	  const status = document.createElement('span'); status.setAttribute('role', 'status');
	  const update = () => {
	    rows.forEach((row, index) => { row.hidden = Math.floor(index / 50) !== page; });
	    status.textContent = rows.length ? ` Rows ${page * 50 + 1}–${Math.min((page + 1) * 50, rows.length)} of ${rows.length} preview rows · Page ${page + 1}/${pages} ` : ' No rows ';
	    previous.disabled = page === 0; next.disabled = page + 1 >= pages;
	  };
	  previous.addEventListener('click', () => { if (page > 0) { page--; update(); } });
	  next.addEventListener('click', () => { if (page + 1 < pages) { page++; update(); } });
	  previous.setAttribute('aria-label', 'Previous database page'); next.setAttribute('aria-label', 'Next database page');
	  controls.append(previous, status, next); update();
	}
	const picker = document.getElementById('glance-database-table');
	picker.addEventListener('change', () => tables.forEach(section => {
	  section.hidden = picker.value !== 'all' && section.dataset.table !== picker.value;
	  if (picker.value !== 'all') section.open = !section.hidden;
	}));
	if (tables.length) { picker.value = tables[0].dataset.table; picker.dispatchEvent(new Event('change')); }
	"""
}
