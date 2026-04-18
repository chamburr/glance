import Foundation

enum PreviewFileType: Equatable {
	case code
	case jupyter
	case markdown
	case sevenZip
	case tar
	case tsv
	case unsupported
	case zip
}

enum PreviewSupport {
	private static let dotfileLexers = [
		// Files with syntax supported by Chroma
		".bashrc": ".bashrc",
		".vimrc": ".vimrc",
		".zprofile": "zsh",
		".zshrc": ".zshrc",
		"dockerfile": "Dockerfile",
		"gemfile": "Gemfile",
		"gnumakefile": "Makefile",
		"makefile": "Makefile",
		"pkgbuild": "PKGBUILD",
		"rakefile": "Rakefile",

		// Files for which a different, similar syntax is used
		".dockerignore": "bash",
		".editorconfig": "ini",
		".gitattributes": "bash",
		".gitconfig": "ini",
		".gitignore": "bash",
		".npmignore": "bash",
		".zsh_history": "txt",
	]

	private static let fileExtensionLexers = [
		// Files with syntax supported by Chroma
		"alfredappearance": "json",
		"mobileconfig": "xml",
		"cjs": "js",
		"cls": "tex",
		"csproj": "xml",
		"entitlements": "xml",
		"hbs": "handlebars",
		"iml": "xml",
		"mjs": "js",
		"plist": "xml",
		"props": "xml",
		"resolved": "json",
		"scpt": "applescript",
		"scptd": "applescript",
		"spf": "xml",
		"spTheme": "xml",
		"storyboard": "xml",
		"stringsdict": "xml",
		"sty": "tex",
		"targets": "xml",
		"webmanifest": "json",
		"xcscheme": "xml",
		"xib": "xml",
		"xmp": "xml",

		// Files for which a different, similar syntax is used
		"ass": "txt",
		"liquid": "twig",
		"lrc": "txt",
		"modulemap": "hcl",
		"nfo": "txt",
		"njk": "twig",
		"pbxproj": "txt",
		"sln": "txt",
		"srt": "txt",
		"strings": "c",
		"ttml": "xml",
		"vtt": "txt",
	]

	static func getCodeLexer(fileURL: URL) -> String {
		if fileURL.pathExtension.isEmpty {
			return dotfileLexers[fileURL.lastPathComponent.lowercased(), default: "autodetect"]
		} else if fileURL.pathExtension.lowercased() == "dist" {
			return getCodeLexer(fileURL: fileURL.deletingPathExtension())
		} else {
			return fileExtensionLexers[
				fileURL.pathExtension.lowercased(),
				default: fileURL.pathExtension
			]
		}
	}

	static func getPreviewFileType(fileURL: URL) -> PreviewFileType {
		switch fileURL.pathExtension.lowercased() {
			case "gz":
				return fileURL.path.hasSuffix(".tar.gz") ? .tar : .unsupported
			case "md", "markdown", "mdown", "mkdn", "mkd", "rmd", "qmd":
				return .markdown
			case "ipynb":
				return .jupyter
			case "tar", "tgz":
				return .tar
			case "tab", "tsv":
				return .tsv
			case "7z":
				return .sevenZip
			case "ear", "jar", "war", "zip":
				return .zip
			default:
				return .code
		}
	}
}
