import Foundation
import WebKit
import XCTest

final class PreviewSmokeTests: XCTestCase {
	private var temporaryDirectory: URL!

	override func setUpWithError() throws {
		try super.setUpWithError()
		temporaryDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlancePreviewTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(
			at: temporaryDirectory,
			withIntermediateDirectories: true
		)
	}

	override func tearDownWithError() throws {
		if let temporaryDirectory {
			try? FileManager.default.removeItem(at: temporaryDirectory)
		}
		try super.tearDownWithError()
	}

	func testCodePreviewHandlesEmptyAndUnicodeSource() throws {
		let fileURL = try writeFile(named: "unicode.swift", contents: "let cafe = \"\u{2615}\"\n")

		let previewVC = try CodePreview().createPreviewVC(file: File(url: fileURL))

		XCTAssertTrue(previewVC is WebPreviewVC)
	}

	func testMarkdownPreviewHandlesFrontMatterAndRawHTML() throws {
		let markdown = """
		---
		title: Fixture
		---

		# Heading

		<script>alert("bad")</script>
		"""
		let fileURL = try writeFile(named: "README.md", contents: markdown)

		let previewVC = try MarkdownPreview().createPreviewVC(file: File(url: fileURL))

		XCTAssertTrue(previewVC is WebPreviewVC)
	}

	func testJupyterPreviewHandlesValidNotebookAndRejectsMalformedNotebook() throws {
		let notebook = """
		{"cells":[{"cell_type":"markdown","metadata":{},"source":["# Heading"]}],"metadata":{},"nbformat":4,"nbformat_minor":4}
		"""
		let validURL = try writeFile(named: "notebook.ipynb", contents: notebook)
		let invalidURL = try writeFile(named: "invalid.ipynb", contents: "not-json")

		let previewVC = try JupyterPreview().createPreviewVC(file: File(url: validURL))

		XCTAssertTrue(previewVC is WebPreviewVC)
		XCTAssertThrowsError(try JupyterPreview().createPreviewVC(file: File(url: invalidURL)))
	}

	func testWebPreviewViewIsVisibleImmediatelyAfterLoading() throws {
		let previewVC = WebPreviewVC(html: "<p>Visible content</p>")

		previewVC.loadViewIfNeeded()

		let webView = try XCTUnwrap(previewVC.view.subviews.compactMap { $0 as? WKWebView }.first)
		XCTAssertFalse(webView.isHidden)
		XCTAssertEqual(webView.alphaValue, 1)
	}

	func testWebPreviewRendersInlineContentAndStyles() throws {
		let previewVC = WebPreviewVC(html: "<p>Visible content</p>")
		previewVC.loadViewIfNeeded()

		let webView = try XCTUnwrap(previewVC.view.subviews.compactMap { $0 as? WKWebView }.first)
		let expectation = expectation(description: "web preview rendered")

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
			webView.evaluateJavaScript(
				"document.body.textContent.trim() + '|' + document.styleSheets.length"
			) { result, error in
				XCTAssertNil(error)
				let renderedState = result as? String
				XCTAssertEqual(renderedState?.hasPrefix("Visible content|"), true)
				let styleSheetCount = Int(renderedState?.split(separator: "|").last ?? "0") ?? 0
				XCTAssertGreaterThan(styleSheetCount, 0)
				expectation.fulfill()
			}
		}

		wait(for: [expectation], timeout: 5)
	}

	func testTSVPreviewHandlesQuotedTabsUnicodeAndBlankCells() throws {
		let tsv = """
		name\tvalue
		cafe\t"one\ttwo"
		blank\t
		"""
		let fileURL = try writeFile(named: "table.tsv", contents: tsv)

		let previewVC = try XCTUnwrap(
			TSVPreview().createPreviewVC(file: File(url: fileURL)) as? TablePreviewVC
		)

		XCTAssertEqual(previewVC.headers, ["name", "value"])
		XCTAssertEqual(previewVC.cells[0]["name"], "cafe")
		XCTAssertEqual(previewVC.cells[0]["value"], "one\ttwo")
		XCTAssertEqual(previewVC.cells[1]["name"], "blank")
		XCTAssertEqual(previewVC.cells[1]["value"], "")
	}

	func testTSVPreviewToleratesMalformedQuotesAsCellText() throws {
		let fileURL = try writeFile(named: "malformed.tsv", contents: "name\tvalue\n\"unterminated\tvalue\n")

		let previewVC = try XCTUnwrap(
			TSVPreview().createPreviewVC(file: File(url: fileURL)) as? TablePreviewVC
		)

		XCTAssertEqual(previewVC.headers, ["name", "value"])
		XCTAssertEqual(previewVC.cells.count, 1)
	}

	func testZIPPreviewHandlesNestedEntriesAndIgnoresResourceForkFolder() throws {
		let zipRoot = temporaryDirectory.appendingPathComponent("zip-root", isDirectory: true)
		try FileManager.default.createDirectory(at: zipRoot, withIntermediateDirectories: true)
		_ = try writeFile(named: "zip-root/folder/nested file.txt", contents: "nested")
		_ = try writeFile(named: "zip-root/__MACOSX/._nested file.txt", contents: "metadata")
		let zipURL = temporaryDirectory.appendingPathComponent("archive.zip")
		try runProcess("/usr/bin/zip", arguments: ["-qry", zipURL.path, "folder", "__MACOSX"], in: zipRoot)

		let previewVC = try XCTUnwrap(
			ZIPPreview().createPreviewVC(file: File(url: zipURL)) as? OutlinePreviewVC
		)

		XCTAssertNotNil(node(named: "folder", in: previewVC.rootNodes))
		XCTAssertNil(node(named: "__MACOSX", in: previewVC.rootNodes))
	}

	func testZIPPreviewRejectsCorruptedArchive() throws {
		let fileURL = try writeFile(named: "corrupted.zip", contents: "not-a-zip")

		XCTAssertThrowsError(try ZIPPreview().createPreviewVC(file: File(url: fileURL)))
	}

	func testTARPreviewHandlesTarAndGzippedTarArchives() throws {
		let tarRoot = temporaryDirectory.appendingPathComponent("tar-root", isDirectory: true)
		try FileManager.default.createDirectory(at: tarRoot, withIntermediateDirectories: true)
		_ = try writeFile(named: "tar-root/folder/nested file.txt", contents: "nested")
		_ = try writeFile(named: "tar-root/folder/unicode-\u{00E9}.txt", contents: "unicode")
		let tarURL = temporaryDirectory.appendingPathComponent("archive.tar")
		let tgzURL = temporaryDirectory.appendingPathComponent("archive.tgz")
		try runProcess("/usr/bin/tar", arguments: ["-cf", tarURL.path, "-C", tarRoot.path, "folder"])
		try runProcess("/usr/bin/tar", arguments: ["-czf", tgzURL.path, "-C", tarRoot.path, "folder"])

		let tarPreviewVC = try XCTUnwrap(
			TARPreview().createPreviewVC(file: File(url: tarURL)) as? OutlinePreviewVC
		)
		let tgzPreviewVC = try XCTUnwrap(
			TARPreview().createPreviewVC(file: File(url: tgzURL)) as? OutlinePreviewVC
		)

		XCTAssertNotNil(node(named: "folder", in: tarPreviewVC.rootNodes))
		XCTAssertNotNil(node(named: "folder", in: tgzPreviewVC.rootNodes))
	}

	func testArchivePreviewsRejectCorruptedTarAndSevenZipFiles() throws {
		let tarURL = try writeFile(named: "corrupted.tar", contents: "not-a-tar")
		let sevenZipURL = try writeFile(named: "corrupted.7z", contents: "not-a-sevenzip")

		XCTAssertThrowsError(try TARPreview().createPreviewVC(file: File(url: tarURL)))
		XCTAssertThrowsError(try SevenZipPreview().createPreviewVC(file: File(url: sevenZipURL)))
	}

	private func writeFile(named name: String, contents: String) throws -> URL {
		let fileURL = temporaryDirectory.appendingPathComponent(name)
		try FileManager.default.createDirectory(
			at: fileURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try contents.write(to: fileURL, atomically: true, encoding: .utf8)
		return fileURL
	}

	private func node(named name: String, in nodes: [FileTreeNode]) -> FileTreeNode? {
		nodes.first { $0.name == name }
	}

	private func runProcess(_ executable: String, arguments: [String], in directory: URL? = nil) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		process.currentDirectoryURL = directory

		let outputPipe = Pipe()
		process.standardOutput = outputPipe
		process.standardError = outputPipe

		try process.run()
		process.waitUntilExit()

		guard process.terminationStatus == 0 else {
			let output = String(
				data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
				encoding: .utf8
			) ?? ""
			throw ProcessError(command: ([executable] + arguments).joined(separator: " "), output: output)
		}
	}
}

private struct ProcessError: Error, CustomStringConvertible {
	let command: String
	let output: String

	var description: String {
		"Command failed: \(command)\n\(output)"
	}
}
