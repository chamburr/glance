import Foundation

enum SupportedPreviewGroup: CaseIterable {
	case archive
	case markdown
	case jupyter
	case tsv
	case code

	var title: String {
		switch self {
			case .archive:
				"Archive"
			case .markdown:
				"Markdown"
			case .jupyter:
				"Jupyter Notebook"
			case .tsv:
				"Tab-separated values"
			case .code:
				"Source code and text"
		}
	}

	var idPrefix: String {
		switch self {
			case .archive:
				"archive"
			case .markdown:
				"markdown"
			case .jupyter:
				"jupyter"
			case .tsv:
				"tsv"
			case .code:
				"code"
		}
	}
}

struct SupportedPreviewType: Equatable {
	let id: String
	let displayName: String
	let group: SupportedPreviewGroup
	let searchTokens: [String]
	let previewFileType: PreviewFileType

	/// The Chroma lexer name to use for syntax highlighting. Only meaningful for `.code` entries.
	/// When `nil`, `getCodeLexer` falls back to the file extension or `"autodetect"`.
	let codeLexer: String?

	let matchRule: SupportedPreviewMatchRule

	func matches(fileURL: URL) -> Bool {
		matchRule.matches(fileURL: fileURL)
	}

	func matchesSearch(_ query: String) -> Bool {
		let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !normalizedQuery.isEmpty else { return true }

		return ([displayName, group.title] + searchTokens)
			.map { $0.lowercased() }
			.contains { $0.contains(normalizedQuery) }
	}
}

enum SupportedPreviewMatchRule: Equatable {
	case any([SupportedPreviewMatchRule])
	case fileExtension(String)
	case fileName(String)
	case pathSuffix(String)

	/// Catch-all for files not matched by any specific rule. Matches everything except bare
	/// `.gz` files (which are not previewable as text). This exists because Glance treats any
	/// unrecognized file as a potential source/text file and attempts syntax-highlighted rendering.
	case defaultTextFallback

	func matches(fileURL: URL) -> Bool {
		switch self {
			case let .any(rules):
				rules.contains { $0.matches(fileURL: fileURL) }
			case let .fileExtension(fileExtension):
				fileURL.pathExtension.lowercased() == fileExtension.lowercased()
			case let .fileName(fileName):
				fileURL.lastPathComponent.lowercased() == fileName.lowercased()
			case let .pathSuffix(pathSuffix):
				fileURL.path(percentEncoded: false).lowercased().hasSuffix(pathSuffix.lowercased())
			case .defaultTextFallback:
				fileURL.pathExtension.lowercased() != "gz"
		}
	}
}

enum SupportedPreviewRegistry {
	static let all: [SupportedPreviewType] = [
		pathSuffixEntry(
			id: "archive.extension.tar-gz",
			displayName: ".tar.gz",
			group: .archive,
			pathSuffix: ".tar.gz",
			previewFileType: .tar,
			searchTokens: ["tar", "gzip", "archive"]
		),
		extensionEntry("7z", group: .archive, previewFileType: .sevenZip, searchTokens: ["7-zip"]),
		extensionEntry("ear", group: .archive, previewFileType: .zip, searchTokens: ["java", "archive"]),
		extensionEntry("jar", group: .archive, previewFileType: .zip, searchTokens: ["java", "archive"]),
		extensionEntry("tar", group: .archive, previewFileType: .tar, searchTokens: ["archive"]),
		extensionEntry("tgz", group: .archive, previewFileType: .tar, searchTokens: ["gzip", "tar"]),
		extensionEntry("war", group: .archive, previewFileType: .zip, searchTokens: ["java", "archive"]),
		extensionEntry("zip", group: .archive, previewFileType: .zip, searchTokens: ["archive"]),

		extensionEntry("md", group: .markdown, previewFileType: .markdown, searchTokens: ["markdown"]),
		extensionEntry("markdown", group: .markdown, previewFileType: .markdown),
		extensionEntry("mdown", group: .markdown, previewFileType: .markdown),
		extensionEntry("mkdn", group: .markdown, previewFileType: .markdown),
		extensionEntry("mkd", group: .markdown, previewFileType: .markdown),
		extensionEntry("rmd", group: .markdown, previewFileType: .markdown, searchTokens: ["R Markdown"]),
		extensionEntry("qmd", group: .markdown, previewFileType: .markdown, searchTokens: ["Quarto"]),

		extensionEntry("ipynb", group: .jupyter, previewFileType: .jupyter, searchTokens: ["notebook"]),

		extensionEntry("tab", group: .tsv, previewFileType: .tsv),
		extensionEntry("tsv", group: .tsv, previewFileType: .tsv),

		fileNameEntry(".bashrc", group: .code, codeLexer: ".bashrc", searchTokens: ["bash", "shell"]),
		fileNameEntry(".dockerignore", group: .code, codeLexer: "bash", searchTokens: ["Docker", "ignore"]),
		fileNameEntry(".editorconfig", group: .code, codeLexer: "ini", searchTokens: ["EditorConfig", "ini"]),
		elrcEntry(),
		fileNameEntry(".gitattributes", group: .code, codeLexer: "bash", searchTokens: ["git"]),
		fileNameEntry(".gitconfig", group: .code, codeLexer: "ini", searchTokens: ["git", "ini"]),
		fileNameEntry(".gitignore", group: .code, codeLexer: "bash", searchTokens: ["git", "ignore"]),
		fileNameEntry(".npmignore", group: .code, codeLexer: "bash", searchTokens: ["npm", "ignore"]),
		fileNameEntry(".vimrc", group: .code, codeLexer: ".vimrc", searchTokens: ["vim"]),
		fileNameEntry(".zprofile", group: .code, codeLexer: "zsh", searchTokens: ["zsh", "shell"]),
		fileNameEntry(".zsh_history", group: .code, codeLexer: "txt", searchTokens: ["zsh", "shell"]),
		fileNameEntry(".zshrc", group: .code, codeLexer: ".zshrc", searchTokens: ["zsh", "shell"]),
		fileNameEntry("Dockerfile", group: .code, codeLexer: "Dockerfile", searchTokens: ["Docker"]),
		fileNameEntry("Gemfile", group: .code, codeLexer: "Gemfile", searchTokens: ["Ruby"]),
		fileNameEntry("GNUmakefile", group: .code, codeLexer: "Makefile", searchTokens: ["Makefile"]),
		fileNameEntry("Makefile", group: .code, codeLexer: "Makefile", searchTokens: ["make"]),
		fileNameEntry("PKGBUILD", group: .code, codeLexer: "PKGBUILD", searchTokens: ["Arch Linux"]),
		fileNameEntry("Rakefile", group: .code, codeLexer: "Rakefile", searchTokens: ["Ruby", "Rake"]),

		extensionEntry("alfredappearance", group: .code, codeLexer: "json", searchTokens: ["Alfred", "JSON"]),
		extensionEntry("ass", group: .code, codeLexer: "txt", searchTokens: ["subtitle"]),
		extensionEntry("cjs", group: .code, codeLexer: "js", searchTokens: ["JavaScript"]),
		extensionEntry("cls", group: .code, codeLexer: "tex", searchTokens: ["TeX", "LaTeX"]),
		extensionEntry("csproj", group: .code, codeLexer: "xml", searchTokens: ["C#", "XML"]),
		extensionEntry("entitlements", group: .code, codeLexer: "xml", searchTokens: ["Xcode", "XML"]),
		extensionEntry("hbs", group: .code, codeLexer: "handlebars", searchTokens: ["Handlebars"]),
		extensionEntry("iml", group: .code, codeLexer: "xml", searchTokens: ["IntelliJ", "XML"]),
		extensionEntry("liquid", group: .code, codeLexer: "twig", searchTokens: ["Liquid", "Twig"]),
		extensionEntry("lrc", group: .code, codeLexer: "txt", searchTokens: ["lyrics"]),
		extensionEntry("mjs", group: .code, codeLexer: "js", searchTokens: ["JavaScript"]),
		extensionEntry("mobileconfig", group: .code, codeLexer: "xml", searchTokens: ["configuration", "XML"]),
		extensionEntry("modulemap", group: .code, codeLexer: "hcl", searchTokens: ["Clang", "module map"]),
		extensionEntry("nfo", group: .code, codeLexer: "txt", searchTokens: ["text"]),
		extensionEntry("njk", group: .code, codeLexer: "twig", searchTokens: ["Nunjucks", "Twig"]),
		extensionEntry("pbxproj", group: .code, codeLexer: "txt", searchTokens: ["Xcode"]),
		extensionEntry("plist", group: .code, codeLexer: "xml", searchTokens: ["property list", "XML"]),
		extensionEntry("props", group: .code, codeLexer: "xml", searchTokens: ["MSBuild", "XML"]),
		extensionEntry("resolved", group: .code, codeLexer: "json", searchTokens: ["Swift Package Manager", "lockfile"]),
		extensionEntry("scpt", group: .code, codeLexer: "applescript", searchTokens: ["AppleScript"]),
		extensionEntry("scptd", group: .code, codeLexer: "applescript", searchTokens: ["AppleScript"]),
		extensionEntry("sln", group: .code, codeLexer: "txt", searchTokens: ["Visual Studio"]),
		extensionEntry("spf", group: .code, codeLexer: "xml", searchTokens: ["Sequel Pro", "XML"]),
		extensionEntry("sptheme", group: .code, codeLexer: "xml", searchTokens: ["Sequel Pro", "XML"]),
		extensionEntry("srt", group: .code, codeLexer: "txt", searchTokens: ["SubRip", "subtitle"]),
		extensionEntry("storyboard", group: .code, codeLexer: "xml", searchTokens: ["Xcode", "XML"]),
		extensionEntry("strings", group: .code, codeLexer: "c", searchTokens: ["Xcode", "localization"]),
		extensionEntry("stringsdict", group: .code, codeLexer: "xml", searchTokens: ["Xcode", "localization", "XML"]),
		extensionEntry("sty", group: .code, codeLexer: "tex", searchTokens: ["TeX", "LaTeX"]),
		extensionEntry("targets", group: .code, codeLexer: "xml", searchTokens: ["MSBuild", "XML"]),
		extensionEntry("ttml", group: .code, codeLexer: "xml", searchTokens: ["Timed Text", "XML"]),
		extensionEntry("vtt", group: .code, codeLexer: "txt", searchTokens: ["WebVTT", "subtitle"]),
		extensionEntry("webmanifest", group: .code, codeLexer: "json", searchTokens: ["web app manifest", "JSON"]),
		extensionEntry("xcscheme", group: .code, codeLexer: "xml", searchTokens: ["Xcode", "XML"]),
		extensionEntry("xib", group: .code, codeLexer: "xml", searchTokens: ["Xcode", "XML"]),
		extensionEntry("xmp", group: .code, codeLexer: "xml", searchTokens: ["XML"]),

		SupportedPreviewType(
			id: "code.other-source-text",
			displayName: "Other source/text files",
			group: .code,
			searchTokens: ["source", "text", "plain text", "code", "autodetect"],
			previewFileType: .code,
			codeLexer: nil,
			matchRule: .defaultTextFallback
		)
	]

	static func entries(in group: SupportedPreviewGroup) -> [SupportedPreviewType] {
		all.filter { $0.group == group }
	}

	static func entry(matching fileURL: URL) -> SupportedPreviewType? {
		all.first { $0.matches(fileURL: fileURL) }
	}

	static var allIDs: Set<String> {
		Set(all.map(\.id))
	}

	private static func extensionEntry(
		_ fileExtension: String,
		group: SupportedPreviewGroup,
		previewFileType: PreviewFileType = .code,
		codeLexer: String? = nil,
		searchTokens: [String] = []
	) -> SupportedPreviewType {
		SupportedPreviewType(
			id: "\(group.idPrefix).extension.\(normalizedIDComponent(fileExtension))",
			displayName: ".\(fileExtension)",
			group: group,
			searchTokens: [fileExtension] + searchTokens,
			previewFileType: previewFileType,
			codeLexer: codeLexer,
			matchRule: .fileExtension(fileExtension)
		)
	}

	private static func fileNameEntry(
		_ fileName: String,
		group: SupportedPreviewGroup,
		codeLexer: String? = nil,
		searchTokens: [String] = []
	) -> SupportedPreviewType {
		SupportedPreviewType(
			id: "\(group.idPrefix).filename.\(normalizedIDComponent(fileName))",
			displayName: fileName,
			group: group,
			searchTokens: [fileName] + searchTokens,
			previewFileType: .code,
			codeLexer: codeLexer,
			matchRule: .fileName(fileName)
		)
	}

	private static func pathSuffixEntry(
		id: String,
		displayName: String,
		group: SupportedPreviewGroup,
		pathSuffix: String,
		previewFileType: PreviewFileType,
		searchTokens: [String] = []
	) -> SupportedPreviewType {
		SupportedPreviewType(
			id: id,
			displayName: displayName,
			group: group,
			searchTokens: [displayName] + searchTokens,
			previewFileType: previewFileType,
			codeLexer: nil,
			matchRule: .pathSuffix(pathSuffix)
		)
	}

	private static func elrcEntry() -> SupportedPreviewType {
		SupportedPreviewType(
			id: "code.extension.elrc",
			displayName: ".elrc",
			group: .code,
			searchTokens: [".elrc", "elrc", "Emacs Lisp", "elisp"],
			previewFileType: .code,
			codeLexer: "elisp",
			matchRule: .any([
				.fileName(".elrc"),
				.fileExtension("elrc")
			])
		)
	}

	private static func normalizedIDComponent(_ value: String) -> String {
		value
			.lowercased()
			.replacingOccurrences(of: ".", with: "")
			.replacingOccurrences(of: "+", with: "plus")
			.replacingOccurrences(of: "_", with: "-")
	}
}
