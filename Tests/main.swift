// swiftformat:disable wrapMultilineStatementBraces
import Cocoa
import SQLite3
import WebKit

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
var failures = 0
func check(_ condition: Bool, _ message: String) {
	if condition {
		print("PASS: \(message)")
	} else {
		print("FAIL: \(message)"); failures += 1
	}
}

func wait(until condition: () -> Bool, seconds: TimeInterval = 15) -> Bool {
	let deadline = Date().addingTimeInterval(seconds)
	while !condition(),
	      Date() < deadline {
		RunLoop.current.run(until: Date().addingTimeInterval(0.02))
	}
	return condition()
}

func javascript(_ script: String, in controller: WebPreviewVC) -> Any? {
	var done = false
	var result: Any?
	controller.webView.evaluateJavaScript(script) { value, error in
		if let error = error {
			print("JavaScript: \(error.localizedDescription)")
		}
		result = value; done = true
	}
	_ = wait(until: { done })
	return result
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
	.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
print("TEST_OUTPUT=\(directory.path)")
let markdown = directory.appendingPathComponent("preview.md")
try """
# Developer previews

## Diagram

```mermaid
flowchart LR
 A[Code] --> B[Preview]
```

## Math

$$E = mc^2$$

> [!WARNING]
> Verify the preview before sharing.

```text
[!NOTE] stays literal in code
```

<script>window.untrustedScriptExecuted = true</script>

[Remote](https://example.com)
""".write(to: markdown, atomically: true, encoding: .utf8)
let controller = try MarkdownPreview().createPreviewVC(file: File(url: markdown)) as! WebPreviewVC
let window = NSWindow(
	contentRect: NSRect(x: -3000, y: -3000, width: 1000, height: 750),
	styleMask: [.borderless],
	backing: .buffered,
	defer: false
)
window.contentViewController = controller
controller.view.layoutSubtreeIfNeeded()
check(
	wait(until: { javascript(
		"window.glanceReady === true && !!document.querySelector('.mermaid svg')",
		in: controller
	) as? Bool == true }),
	"Markdown and bundled Mermaid finish rendering"
)
check(
	javascript("document.querySelectorAll('.katex').length > 0", in: controller) as? Bool == true,
	"KaTeX math renders offline"
)
check(
	javascript(
		"document.querySelectorAll('#glance-toc a').length === 3",
		in: controller
	) as? Bool ==
		true,
	"Contents contains heading anchors"
)
check(
	javascript("window.untrustedScriptExecuted === undefined", in: controller) as? Bool == true,
	"Markdown script is not executed"
)
check(
	javascript(
		"document.querySelector('meta[http-equiv]').content.includes(\"connect-src 'none'\")",
		in: controller
	) as? Bool == true,
	"Network requests blocked by CSP"
)
_ = javascript(
	"window.cspBlocked = false; document.addEventListener('securitypolicyviolation', e => { if (e.violatedDirective === 'connect-src') window.cspBlocked = true; }); fetch('https://example.invalid/').catch(() => {}); true",
	in: controller
)
check(
	wait(until: { javascript("window.cspBlocked", in: controller) as? Bool == true }),
	"WebKit actually rejects network fetches through CSP"
)

check(
	javascript(
		"document.querySelector('.markdown-alert-warning')?.textContent.includes('Verify the preview') === true",
		in: controller
	) as? Bool == true,
	"GitHub warning renders as an accessible callout"
)
check(
	javascript(
		"Array.from(document.querySelectorAll('main pre')).some(pre => pre.textContent.includes('[!NOTE] stays literal in code'))",
		in: controller
	) as? Bool == true,
	"Alert markers inside code remain literal"
)
check(
	javascript(
		"document.querySelector('[aria-label=\"Zoom in diagram\"]') !== null",
		in: controller
	) as? Bool == true,
	"Mermaid has diagram zoom controls"
)

let diagramWidth = javascript(
	"document.querySelector('.mermaid svg').style.width",
	in: controller
) as? String
_ = javascript(
	"document.querySelector('[aria-label=\"Zoom in diagram\"]').click(); true",
	in: controller
)
check(
	(javascript("document.querySelector('.mermaid svg').style.width", in: controller) as? String) !=
		diagramWidth,
	"Mermaid zoom changes diagram scale"
)
_ = javascript(
	"document.querySelector('[aria-label=\"Reset diagram zoom\"]').click(); true",
	in: controller
)
check(
	javascript("document.querySelector('.mermaid svg').style.width", in: controller) as? String ==
		diagramWidth,
	"Mermaid reset restores diagram scale"
)

var toolbarCaptured = false
if let stack = controller.view.subviews.first as? NSStackView,
   let toolbar = stack.arrangedSubviews.first,
   let bitmap = toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds) {
	toolbar.cacheDisplay(in: toolbar.bounds, to: bitmap)
	if let context = CGContext(
		data: nil,
		width: bitmap.pixelsWide,
		height: bitmap.pixelsHigh,
		bitsPerComponent: 8,
		bytesPerRow: 0,
		space: CGColorSpaceCreateDeviceRGB(),
		bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
	),
		let original = bitmap.cgImage {
		let bounds = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
		context.setFillColor(CGColor(gray: 1, alpha: 1))
		context.fill(bounds)
		context.draw(original, in: bounds)
		if let result = context.makeImage(),
		   let png = NSBitmapImageRep(cgImage: result)
		   .representation(using: .png, properties: [:]) {
			try png.write(to: directory.appendingPathComponent("toolbar.png"))
			toolbarCaptured = true
		}
	}
}

check(toolbarCaptured, "Native toolbar screenshot captured for visual inspection")

var snapshotDone = false
controller.webView.takeSnapshot(with: nil) { image, error in
	defer { snapshotDone = true }
	guard let image = image, let tiff = image.tiffRepresentation,
	      let bitmap = NSBitmapImageRep(data: tiff) else {
		print("Snapshot: \(String(describing: error))")
		failures += 1
		return
	}
	guard let png = bitmap.representation(using: .png, properties: [:]) else {
		failures += 1
		return
	}
	do {
		try png.write(to: directory.appendingPathComponent("markdown.png"))
	} catch {
		print(error)
		failures += 1
	}
}

check(wait(until: { snapshotDone }), "WebKit snapshot completed")
let lightFill = javascript(
	"getComputedStyle(document.querySelector('.mermaid svg rect')).fill",
	in: controller
) as? String
controller.webView.appearance = NSAppearance(named: .darkAqua)
check(wait(until: {
	(javascript(
		"getComputedStyle(document.querySelector('.mermaid svg rect')).fill",
		in: controller
	) as? String) != lightFill
}, seconds: 3), "Mermaid redraws when the preview changes to dark appearance")

let jsonURL = directory.appendingPathComponent("data.json")
try #"{"hello":{"n":1}}"#.write(to: jsonURL, atomically: true, encoding: .utf8)
check(
	try CodePreview().getSource(file: File(url: jsonURL)).contains("\n"),
	"JSON is pretty printed"
)
let plistURL = directory.appendingPathComponent("data.plist")
try PropertyListSerialization
	.data(fromPropertyList: ["hello": "world"], format: .binary, options: 0).write(to: plistURL)
check(
	try CodePreview().getSource(file: File(url: plistURL)).contains("<string>world</string>"),
	"Binary plist decompiled without execution"
)
let folder = directory.appendingPathComponent("folder")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try "safe".write(
	to: folder.appendingPathComponent("<unsafe>.txt"),
	atomically: true,
	encoding: .utf8
)
try FileManager.default.createSymbolicLink(
	atPath: folder.appendingPathComponent("loop").path,
	withDestinationPath: folder.path
)
let folderVC = try FolderPreview().createPreviewVC(file: File(url: folder)) as! WebPreviewVC
check(
	folderVC.html.contains("&lt;unsafe&gt;.txt"),
	"Folder names escaped and symlink loop is not followed"
)
let databaseURL = directory.appendingPathComponent("sample.sqlite")
var db: OpaquePointer?
sqlite3_open(databaseURL.path, &db)
sqlite3_exec(
	db,
	"CREATE TABLE sample (name TEXT); INSERT INTO sample VALUES ('<unsafe>');",
	nil,
	nil,
	nil
)
sqlite3_close(db)
let before = try Data(contentsOf: databaseURL)
let dbVC = try DatabasePreview().createPreviewVC(file: File(url: databaseURL)) as! WebPreviewVC
check(dbVC.html.contains("&lt;unsafe&gt;"), "SQLite table is previewed with escaped values")
check(try Data(contentsOf: databaseURL) == before, "SQLite file unchanged by preview")
check(
	!FileManager.default.fileExists(atPath: databaseURL.path + "-journal"),
	"SQLite preview creates no journal"
)
do { _ = try HTMLRenderer.renderNotebook("invalid"); check(false, "Renderer errors propagate")
} catch { check(
	true,
	"Renderer errors propagate"
) }

// Real parsers, not a mirrored reimplementation: duplicate headers, quoting and short rows.
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
_ = csvVC.view
check(csvVC.view.fittingSize.width >= 0, "Native CSV view loads its nib")
for suffix in ["py", "ts", "tsx", "json", "yaml", "toml", "xml", "plist"] {
	let url = directory.appendingPathComponent("routing." + suffix)
	check(
		PreviewVCFactory.getPreviewInitializer(fileURL: url) is CodePreview.Type,
		"Source route: " + suffix
	)
}

check(
	PreviewVCFactory.getPreviewInitializer(fileURL: folder) is FolderPreview.Type,
	"Folder route selected"
)
check(
	PreviewVCFactory.getPreviewInitializer(fileURL: databaseURL) is DatabasePreview.Type,
	"SQLite route selected"
)
let imageURL = directory.appendingPathComponent("local.png")
let bitmap = NSBitmapImageRep(
	bitmapDataPlanes: nil,
	pixelsWide: 2,
	pixelsHigh: 2,
	bitsPerSample: 8,
	samplesPerPixel: 4,
	hasAlpha: true,
	isPlanar: false,
	colorSpaceName: .deviceRGB,
	bytesPerRow: 0,
	bitsPerPixel: 0
)!
try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)
let embedded = MarkdownPreview.inlineLocalImages(
	#"<img src="local.png" alt="local">"#,
	beside: markdown
)
check(
	embedded.contains("data:image/png;base64,"),
	"Accessible local image is embedded without broad file access"
)
let outside = directory.deletingLastPathComponent().appendingPathComponent("outside.png")
try Data(contentsOf: imageURL).write(to: outside)
let blocked = MarkdownPreview.inlineLocalImages(#"<img src="../outside.png">"#, beside: markdown)
check(!blocked.contains("base64"), "Images outside document directory are not read")
let nonImage = directory.appendingPathComponent("fake.png")
try "not an image".write(to: nonImage, atomically: true, encoding: .utf8)
check(
	!MarkdownPreview.inlineLocalImages(#"<img src="fake.png">"#, beside: markdown)
		.contains("base64"),
	"Non-image content is never embedded"
)

let standaloneCSV = try PreviewWindowController(fileURL: csvURL)
check(
	standaloneCSV.window?.contentViewController is TablePreviewVC,
	"Standalone window bypasses Finder's CSV ownership"
)
let typeScriptURL = directory.appendingPathComponent("source.ts")
try "export const answer: number = 42;".write(to: typeScriptURL, atomically: true, encoding: .utf8)
let standaloneTS = try PreviewWindowController(fileURL: typeScriptURL)
check(
	standaloneTS.window?.contentViewController is WebPreviewVC,
	"Standalone window previews TypeScript source without claiming TS video"
)
let documents = directory.appendingPathComponent("docs")
try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
let nestedMarkdown = documents.appendingPathComponent("images.md")
try "![Local](../local.png)".write(to: nestedMarkdown, atomically: true, encoding: .utf8)
let standaloneMarkdown = try PreviewWindowController(fileURL: nestedMarkdown)
try standaloneMarkdown.authorizeImageRoot(directory)
check(
	wait(until: { (standaloneMarkdown.window?.contentViewController as? WebPreviewVC)?.html
			.contains("data:image/png;base64,") == true
	}),
	"Explicit project-folder access supports parent-directory Markdown images"
)
do { _ = try File(url: URL(string: "https://example.com/etc/hosts")!); check(
	false,
	"Remote URLs rejected before reading"
) } catch { check(true, "Remote URLs rejected before reading") }

let standaloneImage = try PreviewWindowController(fileURL: imageURL)
check(
	standaloneImage.window?.contentViewController is NativePreviewVC,
	"Standalone image keeps Apple's native preview inside Glance"
)

// End-to-end table ordering and page boundaries use the real controller.
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
check(
	emptyTable.pageCount == 1 && emptyTable.displayedRows.isEmpty,
	"Empty CSV has a safe empty page"
)
let tableWindow = NSWindow(
	contentRect: NSRect(x: -100_000, y: -100_000, width: 900, height: 650),
	styleMask: [.borderless],
	backing: .buffered,
	defer: false
)
tableWindow.contentViewController = paged
paged.view.layoutSubtreeIfNeeded()
func findTable(in view: NSView) -> NSTableView? {
	if let table = view as? NSTableView {
		return table
	}
	return view.subviews.compactMap { findTable(in: $0) }.first
}

if let nativeTable = findTable(in: paged.view) {
	nativeTable.sortDescriptors = [NSSortDescriptor(key: "0", ascending: true)]
	check(paged.displayedRows.first == ["0"], "Native table sort descriptor drives column ordering")
	check(nativeTable.numberOfRows == 100, "Native table contains only the current page")
} else { check(false, "Native table is present") }
if let image = paged.view.bitmapImageRepForCachingDisplay(in: paged.view.bounds) {
	paged.view.cacheDisplay(in: paged.view.bounds, to: image)
	try image.representation(using: .png, properties: [:])?
		.write(to: directory.appendingPathComponent("table.png"))
}

let patch = """
diff --git a/one.swift b/one.swift
--- a/one.swift
+++ b/one.swift
@@ -1,2 +3,2 @@
-old
+<script>alert(1)</script>
 context
\\ No newline at end of file
diff --git a/two.swift b/two.swift
--- a/two.swift
+++ b/two.swift
@@ -0,0 +1 @@
+new
"""
let patchURL = directory.appendingPathComponent("changes.patch")
try patch.write(to: patchURL, atomically: true, encoding: .utf8)
let diff = try DiffPreview().createPreviewVC(file: File(url: patchURL)) as! WebPreviewVC
let diffWindow = NSWindow(
	contentRect: NSRect(x: -100_000, y: -100_000, width: 1000, height: 750),
	styleMask: [.borderless],
	backing: .buffered,
	defer: false
)
diffWindow.contentViewController = diff
check(
	wait(until: { javascript(
		"document.querySelectorAll('.diff-file').length === 2",
		in: diff
	) as? Bool == true }),
	"Multi-file diff renders both changed files"
)
check(
	javascript(
		"document.querySelector('.diff-remove .diff-number').textContent === '1' && document.querySelector('.diff-add .diff-number:nth-child(2)').textContent === '3'",
		in: diff
	) as? Bool == true,
	"Diff pairs original and new line numbers"
)
check(
	javascript(
		"document.querySelectorAll('main script').length === 0 && document.querySelector('.diff-add').textContent.includes('<script>')",
		in: diff
	) as? Bool == true,
	"Diff HTML is escaped rather than executed"
)
check(
	diff.html.contains("No newline at end of file") && diff.html.contains("Changed files"),
	"Diff retains metadata and file navigation"
)
check(
	PreviewVCFactory.getPreviewInitializer(fileURL: patchURL) is DiffPreview.Type,
	"Patch route selects dedicated diff renderer"
)
check(
	// swiftformat:disable:next numberFormatting
	DiffPreview.renderHTML(source: String(repeating: "+line\n", count: 12_010))
		.contains("Preview limit reached"),
	"Huge diff truncates its displayed rows"
)
check(
	!DiffPreview.renderHTML(source: "@@ -9223372036854775807 +1 @@\n-old\n+new")
		.contains("diff-remove\""),
	"Overflowing diff line numbers safely fall back"
)
var diffSnapshotDone = false
diff.webView.takeSnapshot(with: nil) { image, _ in
	defer { diffSnapshotDone = true }
	if let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
		try? bitmap.representation(using: .png, properties: [:])?
			.write(to: directory.appendingPathComponent("diff.png"))
	}
}

check(wait(until: { diffSnapshotDone }), "Diff screenshot captured")

// Database navigation is deliberately over bounded preview rows, never an unbounded query UI.
var pagingDB: OpaquePointer?
sqlite3_open(databaseURL.path, &pagingDB)
for index in 0 ..< 120 {
	sqlite3_exec(
		pagingDB,
		"INSERT INTO sample VALUES ('row-\(index)');",
		nil,
		nil,
		nil
	)
}

sqlite3_exec(
	pagingDB,
	"CREATE TABLE other (n INTEGER); INSERT INTO other VALUES (42);",
	nil,
	nil,
	nil
)
sqlite3_close(pagingDB)
let pagingBefore = try Data(contentsOf: databaseURL)
let databaseNavigation = try DatabasePreview()
	.createPreviewVC(file: File(url: databaseURL)) as! WebPreviewVC
let dbWindow = NSWindow(
	contentRect: NSRect(x: -100_000, y: -100_000, width: 900, height: 650),
	styleMask: [.borderless],
	backing: .buffered,
	defer: false
)
dbWindow.contentViewController = databaseNavigation
check(
	wait(until: { javascript(
		"document.querySelectorAll('#glance-database-table option').length === 3",
		in: databaseNavigation
	) as? Bool == true }),
	"SQLite table picker lists discovered tables"
)
_ = javascript(
	"document.getElementById('glance-database-table').value = '1'; document.getElementById('glance-database-table').dispatchEvent(new Event('change')); true",
	in: databaseNavigation
)
check(
	javascript(
		"document.querySelectorAll('.glance-database:not([hidden])').length === 1 && document.querySelector('.glance-database:not([hidden]) tbody tr:not([hidden])') !== null",
		in: databaseNavigation
	) as? Bool == true,
	"SQLite picker selects one visible table"
)
check(
	javascript(
		"document.querySelector('.glance-database[data-table=\"1\"] tbody').querySelectorAll('tr:not([hidden])').length === 50",
		in: databaseNavigation
	) as? Bool == true,
	"SQLite shows 50 preview rows per page"
)
_ = javascript(
	"document.querySelector('.glance-database[data-table=\"1\"] [aria-label=\"Next database page\"]').click(); true",
	in: databaseNavigation
)
check(
	javascript(
		"document.querySelector('.glance-database[data-table=\"1\"] [role=status]').textContent.includes('51–100')",
		in: databaseNavigation
	) as? Bool == true,
	"SQLite next page advances through bounded rows"
)
check(
	databaseNavigation.html.contains("title=\"TEXT\""),
	"SQLite column header includes its declared type"
)
check(
	try Data(contentsOf: databaseURL) == pagingBefore,
	"SQLite navigation leaves database bytes unchanged"
)

let liveURL = directory.appendingPathComponent("live.md")
let longDocument = "# Live document\n\n" + (0 ..< 150)
	.map { "Paragraph \($0) has enough content for scrolling.\n\n" }.joined()
try longDocument.write(to: liveURL, atomically: true, encoding: .utf8)
let liveWindow = try PreviewWindowController(fileURL: liveURL)
liveWindow.window?.setFrame(
	NSRect(x: -100_000, y: -100_000, width: 900, height: 650),
	display: false
)
let initialLive = liveWindow.window!.contentViewController as! WebPreviewVC
check(
	wait(until: { javascript("window.glanceReady === true", in: initialLive) as? Bool == true }),
	"Live Markdown initial render is ready"
)
_ = javascript("window.scrollTo(0, 900); true", in: initialLive)
let scrollBefore = (javascript("window.scrollY", in: initialLive) as? NSNumber)?.doubleValue ?? 0
try (longDocument + "\nAtomic save marker\n").write(to: liveURL, atomically: true, encoding: .utf8)
check(
	wait(until: {
		(liveWindow.window?.contentViewController as? WebPreviewVC)?.html
			.contains("Atomic save marker") == true
	}),
	"Live preview detects atomic file replacement"
)
let refreshedLive = liveWindow.window!.contentViewController as! WebPreviewVC
check(wait(until: {
	let scrollAfter = (javascript("window.scrollY", in: refreshedLive) as? NSNumber)?
		.doubleValue ?? 0
	return scrollBefore > 0 && abs(scrollAfter - scrollBefore) < 3
}), "Live refresh preserves the actual scroll position")
let movedLive = directory.appendingPathComponent("live-moving.md")
try FileManager.default.moveItem(at: liveURL, to: movedLive)
_ = wait(until: { false }, seconds: 0.8)
check(
	liveWindow.window?.contentViewController === refreshedLive,
	"A temporarily missing file retains the last good preview"
)
try FileManager.default.moveItem(at: movedLive, to: liveURL)
liveWindow.window?.close()
try (longDocument + "\nAfter close marker\n").write(to: liveURL, atomically: true, encoding: .utf8)
_ = wait(until: { false }, seconds: 0.8)
check(
	liveWindow.window?.contentViewController == nil,
	"Closing the preview stops refresh and releases its view"
)

print("Failures: \(failures)")
exit(failures == 0 ? 0 : 1)
