import Foundation

/// Returns a `PreviewVC` subclass that can be used to generate a preview of the provided file.
/// May return `nil` if the file is not supported.
class PreviewVCFactory {
	static func getPreviewInitializer(fileURL: URL) -> Preview.Type? {
		if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
			return FolderPreview.self
		}
		switch fileURL.pathExtension.lowercased() {
			case "diff", "patch":
				return DiffPreview.self
			case "gz":
				// `gzip` is only supported for tarballs
				return fileURL.path.hasSuffix(".tar.gz") ? TARPreview.self : nil
			case "md", "markdown", "mdown", "mkdn", "mkd", "rmd", "qmd":
				return MarkdownPreview.self
			case "sqlite", "sqlite3", "db":
				return DatabasePreview.self
			case "ipynb":
				return JupyterPreview.self
			case "tar", "tgz":
				return TARPreview.self
			case "tab", "tsv", "csv":
				return TSVPreview.self
			case "7z":
				return SevenZipPreview.self
			case "ear", "jar", "war", "zip":
				return ZIPPreview.self
			default:
				return CodePreview.self
		}
	}
}
