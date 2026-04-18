import XCTest
@testable import Glance

final class PreviewSupportTests: XCTestCase {
	func testPreviewTypeUsesCodePreviewForToml() {
		let fileURL = URL(fileURLWithPath: "/tmp/example.toml")

		XCTAssertEqual(PreviewSupport.getPreviewFileType(fileURL: fileURL), .code)
	}

	func testPreviewTypeUsesCodePreviewForTtml() {
		let fileURL = URL(fileURLWithPath: "/tmp/example.ttml")

		XCTAssertEqual(PreviewSupport.getPreviewFileType(fileURL: fileURL), .code)
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
