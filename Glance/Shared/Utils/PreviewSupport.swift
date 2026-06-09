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
	static func getCodeLexer(fileURL: URL) -> String {
		// Recurse through .dist wrapper extensions
		if fileURL.pathExtension.lowercased() == "dist" {
			return getCodeLexer(fileURL: fileURL.deletingPathExtension())
		}

		// Use the registry's codeLexer when available
		if let entry = SupportedPreviewRegistry.entry(matching: fileURL),
		   let lexer = entry.codeLexer
		{
			return lexer
		}

		// Fall back to extension name or autodetect for unknown files
		return fileURL.pathExtension.isEmpty ? "autodetect" : fileURL.pathExtension
	}

	static func getPreviewFileType(fileURL: URL) -> PreviewFileType {
		SupportedPreviewRegistry.entry(matching: fileURL)?.previewFileType ?? .unsupported
	}
}
