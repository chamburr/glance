import XCTest

final class PreviewFactoryTests: XCTestCase {
	func testFactoryReturnsPreviewForEveryPreviewFamilyAlias() {
		let cases: [(path: String, expected: Preview.Type?)] = [
			("/tmp/source.swift", CodePreview.self),
			("/tmp/readme.md", MarkdownPreview.self),
			("/tmp/readme.markdown", MarkdownPreview.self),
			("/tmp/readme.mdown", MarkdownPreview.self),
			("/tmp/readme.mkdn", MarkdownPreview.self),
			("/tmp/readme.mkd", MarkdownPreview.self),
			("/tmp/readme.rmd", MarkdownPreview.self),
			("/tmp/readme.qmd", MarkdownPreview.self),
			("/tmp/notebook.ipynb", JupyterPreview.self),
			("/tmp/archive.tar", TARPreview.self),
			("/tmp/archive.tgz", TARPreview.self),
			("/tmp/archive.tar.gz", TARPreview.self),
			("/tmp/table.tab", TSVPreview.self),
			("/tmp/table.tsv", TSVPreview.self),
			("/tmp/archive.7z", SevenZipPreview.self),
			("/tmp/archive.ear", ZIPPreview.self),
			("/tmp/archive.jar", ZIPPreview.self),
			("/tmp/archive.war", ZIPPreview.self),
			("/tmp/archive.zip", ZIPPreview.self),
			("/tmp/plain.gz", nil),
		]

		for testCase in cases {
			let fileURL = URL(fileURLWithPath: testCase.path)
			XCTAssertTrue(
				PreviewVCFactory.getPreviewInitializer(fileURL: fileURL) == testCase.expected,
				testCase.path
			)
		}
	}
}
