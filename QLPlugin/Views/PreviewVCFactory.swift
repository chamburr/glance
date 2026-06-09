import Foundation

/// Returns a `PreviewVC` subclass that can be used to generate a preview of the provided file.
/// Returns `nil` if the file type is not supported.
class PreviewVCFactory {
	static func getPreviewInitializer(fileURL: URL) -> Preview.Type? {
		guard let entry = SupportedPreviewRegistry.entry(matching: fileURL) else {
			return nil
		}

		switch entry.previewFileType {
			case .markdown:
				return MarkdownPreview.self
			case .jupyter:
				return JupyterPreview.self
			case .tar:
				return TARPreview.self
			case .tsv:
				return TSVPreview.self
			case .sevenZip:
				return SevenZipPreview.self
			case .zip:
				return ZIPPreview.self
			case .code:
				return CodePreview.self
			case .unsupported:
				return nil
		}
	}
}
