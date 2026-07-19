import Foundation
import os.log

class DrawIOPreview: Preview {
	private let mainStylesheetURL = Bundle.main.url(
		forResource: "drawio-main",
		withExtension: "css"
	)
	private let viewerScriptURL = Bundle.main.url(
		forResource: "drawio-viewer.min",
		withExtension: "js"
	)

	required init() {}

	func createPreviewVC(file: File) throws -> PreviewVC {
		let source = try file.read()
		let processed = resolveLightDarkColors(source)
		let html = buildHTML(xml: processed)
		return WebPreviewVC(
			html: html,
			stylesheets: getStylesheets(),
			scripts: getScripts()
		)
	}

	private func getStylesheets() -> [Stylesheet] {
		var stylesheets = [Stylesheet]()
		if let url = mainStylesheetURL {
			stylesheets.append(Stylesheet(url: url))
		} else {
			os_log("Could not find draw.io stylesheet", log: Log.render, type: .error)
		}
		return stylesheets
	}

	private func getScripts() -> [Script] {
		var scripts = [Script]()
		if let url = viewerScriptURL {
			scripts.append(Script(url: url))
		} else {
			os_log("Could not find draw.io viewer script", log: Log.render, type: .error)
		}
		return scripts
	}

	private func buildHTML(xml: String) -> String {
		// Escape the XML for embedding in a JSON attribute
		let escaped = escapeForJSON(xml)

		return """
		<div class="mxgraph" data-mxgraph='{"highlight":"#0000ff","nav":false,"resize":true,"toolbar":"","edit":"_blank","xml":\(
			escaped
		)}'></div>
		"""
	}

	/// Replace `light-dark(light, dark)` CSS values with the distinctive color.
	/// When light is a neutral (#000000/#FFFFFF), use the dark (colored) value instead.
	private func resolveLightDarkColors(_ xml: String) -> String {
		var result = xml
		let pattern = "light-dark\\(\\s*(#[0-9A-Fa-f]{6})\\s*,\\s*(#[0-9A-Fa-f]{6})\\s*\\)"
		guard let regex = try? NSRegularExpression(pattern: pattern) else {
			return xml
		}
		let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
		// Replace in reverse order to preserve ranges
		for match in matches.reversed() {
			guard let fullRange = Range(match.range, in: result),
			      let lightRange = Range(match.range(at: 1), in: result),
			      let darkRange = Range(match.range(at: 2), in: result)
			else { continue }
			let light = String(result[lightRange]).lowercased()
			let dark = String(result[darkRange])
			let replacement = (light == "#000000" || light == "#ffffff") ? dark :
				String(result[lightRange])
			result.replaceSubrange(fullRange, with: replacement)
		}
		return result
	}

	private func escapeForJSON(_ string: String) -> String {
		var result = string
		result = result.replacingOccurrences(of: "\\", with: "\\\\")
		result = result.replacingOccurrences(of: "\"", with: "\\\"")
		result = result.replacingOccurrences(of: "'", with: "\\'")
		result = result.replacingOccurrences(of: "\n", with: "\\n")
		result = result.replacingOccurrences(of: "\r", with: "\\r")
		result = result.replacingOccurrences(of: "\t", with: "\\t")
		return "\"\(result)\""
	}
}
