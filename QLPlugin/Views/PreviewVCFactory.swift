import Foundation

/// Returns a `PreviewVC` subclass that can be used to generate a preview of the provided file.
/// May return `nil` if the file is not supported.
class PreviewVCFactory {
	static func getPreviewInitializer(fileURL: URL) -> Preview.Type? {
		switch fileURL.pathExtension.lowercased() {
			case "gz":
				// `gzip` is only supported for tarballs
				return fileURL.path.hasSuffix(".tar.gz") ? TARPreview.self : nil
			case "md", "markdown", "mdown", "mkdn", "mkd", "rmd", "qmd":
				return MarkdownPreview.self
			case "ipynb":
				return JupyterPreview.self
			case "tar", "tgz":
				return TARPreview.self
			case "tab", "tsv":
				return TSVPreview.self
			case "ear", "jar", "war", "zip":
				return ZIPPreview.self
			default:
				return CodePreview.self
		}
	}
}
