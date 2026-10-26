import Cocoa

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
	precondition(condition(), message)
	checks += 1
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let csvURL = directory.appendingPathComponent("quoted.csv")
try "name,name,notes\nAlice,Bob,\"one,two\"\nCarol\n".write(
	to: csvURL,
	atomically: true,
	encoding: .utf8
)
let csvVC = try TSVPreview().createPreviewVC(file: File(url: csvURL)) as! TablePreviewVC
check(csvVC.headers == ["name", "name", "notes"], "CSV duplicate headers are preserved")
check(csvVC.cells[0] == ["Alice", "Bob", "one,two"], "Quoted CSV cells parse correctly")
check(csvVC.cells[1] == ["Carol"], "Short CSV rows remain safe")

check(PreviewVCFactory.getPreviewInitializer(fileURL: csvURL) is TSVPreview.Type, "CSV routing")
let tsvURL = directory.appendingPathComponent("quoted.TSV")
try "a\tb\n\"one\ttwo\"\tthree\n".write(to: tsvURL, atomically: true, encoding: .utf8)
let tsv = try TSVPreview().createPreviewVC(file: File(url: tsvURL)) as! TablePreviewVC
check(tsv.cells == [["one\ttwo", "three"]], "Quoted tab")
check(PreviewVCFactory.getPreviewInitializer(fileURL: tsvURL) is TSVPreview.Type, "TSV routing")
let sortable = TablePreviewVC(
	headers: ["value", "identity"],
	cells: [["10", "first"], ["2", "second"], ["2", "third"], [], [" ", "blank"]]
)
sortable.applySort(columnIndex: 0, ascending: true)
check(
	sortable.displayedRows.prefix(3).map { $0[1] } == ["second", "third", "first"],
	"Numeric CSV sort is stable"
)
sortable.applySort(columnIndex: 0, ascending: false)
check(
	sortable.displayedRows.prefix(3).map { $0[1] } == ["first", "second", "third"] && sortable
		.displayedRows[3].isEmpty,
	"Descending CSV sort keeps missing and blank cells last"
)
let paged = TablePreviewVC(headers: ["number"], cells: (0 ..< 201).map { [String($0)] })
check(paged.pageCount == 3 && paged.displayedRows.count == 100, "CSV starts with 100 rows per page")
paged.nextPage()
check(
	paged.displayedRows.first == ["100"] && paged.displayedRows.count == 100,
	"CSV next page reaches row 101"
)
paged.nextPage(); paged.nextPage()
check(
	paged.currentPage == 2 && paged.displayedRows == [["200"]],
	"CSV final page and upper boundary are safe"
)
paged.applySort(columnIndex: 0, ascending: false)
check(
	paged.currentPage == 0 && paged.displayedRows.first == ["200"],
	"Sorting CSV resets to the first page"
)
paged.previousPage()
check(paged.currentPage == 0, "CSV previous page cannot pass the start")
let emptyTable = TablePreviewVC(headers: [], cells: [])
check(emptyTable.pageCount == 1 && emptyTable.displayedRows.isEmpty, "Empty pages")

// Instantiate the actual controller in an unshown, offscreen window.
_ = NSApplication.shared
let window = NSWindow(
	contentRect: NSRect(x: -100_000, y: -100_000, width: 900, height: 650),
	styleMask: [.borderless],
	backing: .buffered,
	defer: false
)
func capture(_ view: NSView, name: String) throws {
	view.layoutSubtreeIfNeeded()
	guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds),
	      let data = bitmap.representation(using: .png, properties: [:])
	else { preconditionFailure("Snapshot unavailable") }
	view.cacheDisplay(in: view.bounds, to: bitmap)
	try bitmap.representation(using: .png, properties: [:])!
		.write(to: directory.appendingPathComponent(name + ".png"))
	check(!data.isEmpty, "Snapshot produced")
}

func findTable(in view: NSView) -> NSTableView? {
	if let table = view as? NSTableView {
		return table
	}
	return view.subviews.compactMap { findTable(in: $0) }.first
}

window.contentViewController = csvVC
csvVC.view.layoutSubtreeIfNeeded()
let nativeCSV = findTable(in: csvVC.view)!
check(
	nativeCSV.tableColumns.count == 3 && nativeCSV.numberOfRows == 2,
	"Actual CSV table dimensions"
)
let secondCell = nativeCSV.view(atColumn: 1, row: 0, makeIfNecessary: true) as! NSTextField
check(secondCell.stringValue == "Bob", "Duplicate header renders its own positional cell")
try capture(csvVC.view, name: "csv")
window.contentViewController = paged
paged.view.layoutSubtreeIfNeeded()
let nativePaged = findTable(in: paged.view)!
nativePaged.sortDescriptors = [NSSortDescriptor(key: "0", ascending: true)]
check(paged.displayedRows.first == ["0"] && nativePaged.numberOfRows == 100, "Actual table sorting")
paged.nextPage()
check(
	paged.displayedRows.first == ["100"] && nativePaged.numberOfRows == 100,
	"Actual table page transition"
)
try capture(paged.view, name: "navigation")
func labels(in view: NSView) -> [String] {
	let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
	return own + view.subviews.flatMap { labels(in: $0) }
}

let largeURL = directory.appendingPathComponent("large.csv")
let largeRows = (0 ..< 5002).map { "Invoice \($0 + 1),\($0 + 10),Open" }
try ("Invoice,Amount,Status\n" + largeRows.joined(separator: "\n") + "\n").write(
	to: largeURL,
	atomically: true,
	encoding: .utf8
)
let capped = try TSVPreview().createPreviewVC(file: File(url: largeURL)) as! TablePreviewVC
window.contentViewController = capped
capped.view.layoutSubtreeIfNeeded()
check(capped.cells.count == 5000, "CSV display retains the original 5000-row cap")
check(
	labels(in: capped.view).contains { $0.contains("First 5000 rows only") },
	"Truncation is visible in the actual native footer"
)
try capture(capped.view, name: "csv-table")
check(capped.pageCount == 50, "Pagination covers only the retained preview rows")
let exactURL = directory.appendingPathComponent("exact.csv")
try ("Invoice,Amount,Status\n" + largeRows.prefix(5000).joined(separator: "\n") + "\n").write(
	to: exactURL,
	atomically: true,
	encoding: .utf8
)
let exact = try TSVPreview().createPreviewVC(file: File(url: exactURL)) as! TablePreviewVC
window.contentViewController = exact
exact.view.layoutSubtreeIfNeeded()
check(
	!labels(in: exact.view).contains { $0.contains("rows only") },
	"An exact-limit file is not marked truncated"
)
print("Passed \(checks) headless checks")
