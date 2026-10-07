import Foundation

class ThreeMFPreview: Preview {
	private let dimensionFormatter = NumberFormatter()
	private let triangleFormatter = NumberFormatter()

	required init() {
		dimensionFormatter.numberStyle = .decimal
		dimensionFormatter.maximumFractionDigits = 1
		triangleFormatter.numberStyle = .decimal
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		// 3MF files are exempt from the size limit that applies to other files, because a small
		// container can hold a large model. It still needs a limit of its own: the container's
		// table of contents is read before any of the parser's budgets applies.
		guard file.size <= ThreeMFLimits.maxFileSize else {
			let limit = ByteCountFormatter().string(for: ThreeMFLimits.maxFileSize) ?? "the limit"
			throw ThreeMFError.tooLargeError(reason: "the file is larger than \(limit)")
		}

		let parser = try ThreeMFParser(fileURL: file.url)
		let model = try parser.parse()
		let modelScene = try model.buildScene()

		return ModelPreviewVC(
			scene: modelScene.scene,
			camera: modelScene.camera,
			labelText: buildLabel(scene: modelScene)
		)
	}

	/// Builds a label with the model's dimensions and triangle count, e.g.
	/// "45 × 30 × 12.5 mm — 12,480 triangles".
	private func buildLabel(scene: ThreeMFScene) -> String {
		let dimensions = [scene.dimensions.x, scene.dimensions.y, scene.dimensions.z]
			.map { dimensionFormatter.string(for: $0) ?? "--" }
			.joined(separator: " × ")
		let triangles = triangleFormatter.string(for: scene.triangleCount) ?? "--"
		let unit = scene.triangleCount == 1 ? "triangle" : "triangles"

		return "\(dimensions) mm — \(triangles) \(unit)"
	}
}
