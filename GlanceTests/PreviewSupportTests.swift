import XCTest

final class PreviewSupportTests: XCTestCase {
	func testSupportedPreviewRegistryIDsAreUnique() {
		let ids = SupportedPreviewRegistry.all.map(\.id)

		XCTAssertEqual(Set(ids).count, ids.count)
	}

	func testSupportedPreviewRegistryMatchesAliasesAndFallbacks() throws {
		let cases: [(path: String, expectedID: String?, expectedType: PreviewFileType)] = [
			("/tmp/archive.tar.gz", "archive.extension.tar-gz", .tar),
			("/tmp/ARCHIVE.TAR.GZ", "archive.extension.tar-gz", .tar),
			("/tmp/readme.md", "markdown.extension.md", .markdown),
			("/tmp/README.MD", "markdown.extension.md", .markdown),
			("/tmp/readme.markdown", "markdown.extension.markdown", .markdown),
			("/tmp/notebook.ipynb", "jupyter.extension.ipynb", .jupyter),
			("/tmp/table.tsv", "tsv.extension.tsv", .tsv),
			("/tmp/archive.zip", "archive.extension.zip", .zip),
			("/tmp/archive.7z", "archive.extension.7z", .sevenZip),
			("/tmp/.elrc", "code.extension.elrc", .code),
			("/tmp/config.elrc", "code.extension.elrc", .code),
			("/tmp/Makefile", "code.filename.makefile", .code),
			("/tmp/example.unknownext", "code.other-source-text", .code),
			("/tmp/plain.gz", nil, .unsupported),
		]

		for testCase in cases {
			let fileURL = URL(fileURLWithPath: testCase.path)
			XCTAssertEqual(
				SupportedPreviewRegistry.entry(matching: fileURL)?.id,
				testCase.expectedID,
				testCase.path
			)
			XCTAssertEqual(
				PreviewSupport.getPreviewFileType(fileURL: fileURL),
				testCase.expectedType,
				testCase.path
			)
		}
	}

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
			("/tmp/.elrc", .code),
			("/tmp/config.elrc", .code),
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
			(".elrc", "elisp"),
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
			("elrc", "elisp"),
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
