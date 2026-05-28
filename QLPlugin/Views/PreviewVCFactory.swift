import Foundation

/// Returns a `PreviewVC` subclass that can be used to generate a preview of the provided file.
/// May return `nil` if the file is not supported.
class PreviewVCFactory {
	static func getPreviewInitializer(fileURL: URL) -> Preview.Type? {
		switch PreviewSupport.getPreviewFileType(fileURL: fileURL) {
			case .markdown:
				MarkdownPreview.self
			case .jupyter:
				JupyterPreview.self
			case .tar:
				TARPreview.self
			case .tsv:
				TSVPreview.self
			case .sevenZip:
				SevenZipPreview.self
			case .zip:
				ZIPPreview.self
			case .code:
				CodePreview.self
			case .unsupported:
				nil
		}
	}
}
