import Foundation
import SQLite3

let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }
func check(_ condition: @autoclosure () throws -> Bool) rethrows {
	let result = try condition(); precondition(result)
}

let url = scratch.appendingPathComponent("sample.sqlite")
var db: OpaquePointer?
check(sqlite3_open(url.path, &db) == SQLITE_OK)
check(sqlite3_exec(
	db,
	"CREATE TABLE sample(value TEXT, payload BLOB); INSERT INTO sample VALUES ('<unsafe>', x'0102');",
	nil,
	nil,
	nil
) == SQLITE_OK)
sqlite3_close(db)
let before = try Data(contentsOf: url)
let html = try (DatabasePreview().createPreviewVC(file: File(url: url)) as! WebPreviewVC).html
check(html.contains("&lt;unsafe&gt;")); check(html.contains("[BLOB: 2 bytes]")); check(html
	.contains("glance-database-table"))
try check(try Data(contentsOf: url) == before)
print("PASS SQLite table, escaping, BLOB and unchanged database bytes")
