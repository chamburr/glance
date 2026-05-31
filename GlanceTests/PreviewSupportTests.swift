import XCTest

final class PreviewSupportTests: XCTestCase {
	func testPreviewTypeUsesSpecializedPreviewForSupportedExtensionAliases() {
		let cases: [(path: String, expected: PreviewFileType)] = [
			("/tmp/readme.md", .markdown),
			("/tmp/readme.markdown", .markdown),
			("/tmp/readme.mdown", .markdown),
			("/tmp/readme.mkdn", .markdown),
			("/tmp/readme.mkd", .markdown),
			("/tmp/readme.rmd", .markdown),
			("/tmp/readme.qmd", .markdown),
			("/tmp/notebook.ipynb", .jupyter),
			("/tmp/archive.tar", .tar),
			("/tmp/archive.tgz", .tar),
			("/tmp/archive.tar.gz", .tar),
			("/tmp/table.tab", .tsv),
			("/tmp/table.tsv", .tsv),
			("/tmp/archive.7z", .sevenZip),
			("/tmp/archive.ear", .zip),
			("/tmp/archive.jar", .zip),
			("/tmp/archive.war", .zip),
			("/tmp/archive.zip", .zip),
			("/tmp/archive.gz", .unsupported),
			("/tmp/source.swift", .code),
		]

		for testCase in cases {
			let fileURL = URL(fileURLWithPath: testCase.path)
			XCTAssertEqual(
				PreviewSupport.getPreviewFileType(fileURL: fileURL),
				testCase.expected,
				testCase.path
			)
		}
	}

	func testPreviewTypeIsCaseInsensitive() {
		XCTAssertEqual(
			PreviewSupport.getPreviewFileType(fileURL: URL(fileURLWithPath: "/tmp/README.MD")),
			.markdown
		)
		XCTAssertEqual(
			PreviewSupport.getPreviewFileType(fileURL: URL(fileURLWithPath: "/tmp/ARCHIVE.TAR.GZ")),
			.tar
		)
		XCTAssertEqual(
			PreviewSupport.getPreviewFileType(fileURL: URL(fileURLWithPath: "/tmp/ARCHIVE.ZIP")),
			.zip
		)
	}

	func testCodeLexerUsesDotfileMappings() {
		let cases = [
			(".bashrc", ".bashrc"),
			(".vimrc", ".vimrc"),
			(".zprofile", "zsh"),
			(".zshrc", ".zshrc"),
			("Dockerfile", "Dockerfile"),
			("Gemfile", "Gemfile"),
			("GNUmakefile", "Makefile"),
			("Makefile", "Makefile"),
			("PKGBUILD", "PKGBUILD"),
			("Rakefile", "Rakefile"),
			(".dockerignore", "bash"),
			(".editorconfig", "ini"),
			(".gitattributes", "bash"),
			(".gitconfig", "ini"),
			(".gitignore", "bash"),
			(".npmignore", "bash"),
			(".zsh_history", "txt"),
		]

		for (fileName, lexer) in cases {
			let fileURL = URL(fileURLWithPath: "/tmp/\(fileName)")
			XCTAssertEqual(PreviewSupport.getCodeLexer(fileURL: fileURL), lexer, fileName)
		}
	}

	func testCodeLexerUsesExtensionMappings() {
		let cases = [
			("alfredappearance", "json"),
			("mobileconfig", "xml"),
			("cjs", "js"),
			("cls", "tex"),
			("csproj", "xml"),
			("entitlements", "xml"),
			("hbs", "handlebars"),
			("iml", "xml"),
			("mjs", "js"),
			("plist", "xml"),
			("props", "xml"),
			("resolved", "json"),
			("scpt", "applescript"),
			("scptd", "applescript"),
			("spf", "xml"),
			("spTheme", "xml"),
			("storyboard", "xml"),
			("stringsdict", "xml"),
			("sty", "tex"),
			("targets", "xml"),
			("webmanifest", "json"),
			("xcscheme", "xml"),
			("xib", "xml"),
			("xmp", "xml"),
			("ass", "txt"),
			("liquid", "twig"),
			("lrc", "txt"),
			("modulemap", "hcl"),
			("nfo", "txt"),
			("njk", "twig"),
			("pbxproj", "txt"),
			("sln", "txt"),
			("srt", "txt"),
			("strings", "c"),
			("ttml", "xml"),
			("vtt", "txt"),
		]

		for (fileExtension, lexer) in cases {
			let fileURL = URL(fileURLWithPath: "/tmp/example.\(fileExtension)")
			XCTAssertEqual(
				PreviewSupport.getCodeLexer(fileURL: fileURL),
				lexer,
				fileExtension
			)
		}
	}

	func testCodeLexerRecursesThroughDistExtension() {
		XCTAssertEqual(
			PreviewSupport.getCodeLexer(fileURL: URL(fileURLWithPath: "/tmp/example.swift.dist")),
			"swift"
		)
		XCTAssertEqual(
			PreviewSupport.getCodeLexer(fileURL: URL(fileURLWithPath: "/tmp/example.spTheme.dist")),
			"xml"
		)
	}

	func testCodeLexerFallsBackToExtensionOrAutodetect() {
		XCTAssertEqual(
			PreviewSupport.getCodeLexer(fileURL: URL(fileURLWithPath: "/tmp/example.unknownext")),
			"unknownext"
		)
		XCTAssertEqual(
			PreviewSupport.getCodeLexer(fileURL: URL(fileURLWithPath: "/tmp/unknown-dotless-file")),
			"autodetect"
		)
	}
}
