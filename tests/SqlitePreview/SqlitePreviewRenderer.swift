// swiftformat:disable wrapMultilineStatementBraces
import Cocoa
import SQLite3
import WebKit

@main
struct RendererCheck {
	static func main() throws {
		_ = NSApplication.shared
		let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		func check(_ condition: Bool, _ message: String) {
			precondition(condition, message); print("PASS: \(message)")
		}
		func fixture(_ name: String, _ value: String) throws -> URL {
			let url = directory.appendingPathComponent(name)
			try value.write(to: url, atomically: true, encoding: .utf8)
			return url
		}
		let url = directory.appendingPathComponent("sample.sqlite")
		var db: OpaquePointer?
		check(sqlite3_open(url.path, &db) == SQLITE_OK, "fixture database opens")
		let sql = "CREATE TABLE first(value TEXT); WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<120) INSERT INTO first SELECT 'Row ' || x FROM n; CREATE TABLE second(value TEXT); INSERT INTO second VALUES ('Second table');"
		check(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "fixture tables created")
		sqlite3_close(db)
		let controller = try DatabasePreview().createPreviewVC(file: File(url: url))
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		controller.view.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
		controller.view.layoutSubtreeIfNeeded()
		let web = controller.view.subviews.compactMap { $0 as? WebView }.first!
		func evaluate(_ script: String) -> String { web
			.stringByEvaluatingJavaScript(from: script) ?? ""
		}
		let deadline = Date().addingTimeInterval(10)
		while evaluate("document.body ? document.body.textContent : ''")
			.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			Date() < deadline {
			RunLoop.current.run(until: Date().addingTimeInterval(0.05))
		}
		let text = evaluate("document.body.textContent")
		check(!text.isEmpty, "actual WebView document loaded")
		check(
			evaluate("document.querySelectorAll('#glance-database-table option').length") == "3",
			"table picker contains two tables"
		)
		check(
			evaluate("document.querySelector('.glance-database-pages [role=status]').textContent")
				.contains("Page 1/3"),
			"pagination starts at page one"
		)
		_ = evaluate("document.querySelectorAll('.glance-database-pages button')[1].click()")
		check(
			evaluate("document.querySelector('.glance-database-pages [role=status]').textContent")
				.contains("Page 2/3"),
			"next button changes actual page"
		)
		check(
			evaluate(
				"Array.from(document.querySelectorAll('details:first-of-type tbody tr')).filter(r => !r.hidden).length"
			) ==
				"50",
			"page contains fifty visible rows"
		)
		_ =
			evaluate(
				"document.getElementById('glance-database-table').value='1'; document.getElementById('glance-database-table').dispatchEvent(new Event('change'))"
			)
		check(
			evaluate("document.querySelectorAll('.glance-database')[0].hidden") == "true",
			"picker hides first table"
		)
		check(
			evaluate("document.querySelectorAll('.glance-database')[1].open") == "true",
			"picker opens selected table"
		)
		RunLoop.current.run(until: Date().addingTimeInterval(0.2))
		controller.view.displayIfNeeded()
		let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)!
		controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
		try bitmap.representation(using: .png, properties: [:])!
			.write(to: directory.appendingPathComponent("sqlite-preview.png"))
		check(!window.isVisible, "window remains offscreen")
	}
}
