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
print("Passed \(checks) headless checks")
