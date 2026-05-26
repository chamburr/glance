import XCTest
@testable import Glance

final class PreviewSupportTests: XCTestCase {
	func testPreviewTypeUsesTarPreviewForUppercaseTarGzFiles() {
		let fileURL = URL(fileURLWithPath: "/tmp/example.TAR.GZ")

		XCTAssertEqual(PreviewSupport.getPreviewFileType(fileURL: fileURL), .tar)
	}

	func testPreviewTypeUsesUnsupportedPreviewForPlainGzFiles() {
		let fileURL = URL(fileURLWithPath: "/tmp/example.gz")

		XCTAssertEqual(PreviewSupport.getPreviewFileType(fileURL: fileURL), .unsupported)
	}

	func testPreviewTypeUsesTsvPreviewForTsvFiles() {
		let fileURL = URL(fileURLWithPath: "/tmp/example.tsv")

		XCTAssertEqual(PreviewSupport.getPreviewFileType(fileURL: fileURL), .tsv)
	}

	func testPreviewTypeUsesZipPreviewForZipFiles() {
		let fileURL = URL(fileURLWithPath: "/tmp/example.zip")

		XCTAssertEqual(PreviewSupport.getPreviewFileType(fileURL: fileURL), .zip)
	}

	func testCodeLexerUsesTomlLexerForTomlFiles() {
		let fileURL = URL(fileURLWithPath: "/tmp/example.toml")

		XCTAssertEqual(PreviewSupport.getCodeLexer(fileURL: fileURL), "toml")
	}

	func testCodeLexerUsesXmlLexerForTtmlFiles() {
		let fileURL = URL(fileURLWithPath: "/tmp/example.ttml")

		XCTAssertEqual(PreviewSupport.getCodeLexer(fileURL: fileURL), "xml")
	}

	func testCodeLexerKeepsExistingSubtitleMappings() {
		let fileURL = URL(fileURLWithPath: "/tmp/example.srt")

		XCTAssertEqual(PreviewSupport.getCodeLexer(fileURL: fileURL), "txt")
	}
}
