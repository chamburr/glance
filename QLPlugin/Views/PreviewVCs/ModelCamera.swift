import Cocoa
import SceneKit

/// Camera looking at a model from a three-quarter view. The distance to the model depends on the
/// aspect ratio of the view it is rendered in, so it is only known once the view has been laid out.
class ModelCamera {
	/// Vertical field of view, in degrees
	private static let fieldOfView: CGFloat = 40
	/// Direction the model is looked at from
	private static let direction = SCNVector3(0.55, 0.45, 1)
	/// Empty space kept around the model
	private static let margin: CGFloat = 1.05

	let node: SCNNode

	/// Point the camera looks at
	private let target: SCNVector3
	/// Corners of the model's bounding box, which all have to be visible
	private let corners: [SCNVector3]
	private let radius: CGFloat

	init(target: SCNVector3, corners: [SCNVector3], radius: CGFloat) {
		self.target = target
		self.corners = corners
		self.radius = radius

		let camera = SCNCamera()
		camera.fieldOfView = ModelCamera.fieldOfView
		camera.projectionDirection = .vertical
		// The user can zoom and pan freely, so the visible depth range cannot be computed once
		camera.automaticallyAdjustsZRange = true

		node = SCNNode()
		node.camera = camera
		node.position = SCNVector3(target.x, target.y, target.z + max(radius * 3, 1))
		node.look(at: target)
	}

	/// Moves the camera to the distance at which the whole model is visible.
	func frame(aspectRatio: CGFloat) {
		guard radius > 0, aspectRatio > 0 else {
			return
		}

		let direction = ModelCamera.direction.normalized()
		let distance = self.distance(aspectRatio: aspectRatio, direction: direction)

		node.position = SCNVector3(
			target.x + direction.x * distance,
			target.y + direction.y * distance,
			target.z + direction.z * distance
		)
		node.look(at: target)
	}

	/// Returns the smallest distance from the model's center at which every corner of its bounding
	/// box is inside the field of view.
	private func distance(aspectRatio: CGFloat, direction: SCNVector3) -> CGFloat {
		// Basis of the camera, which looks at the target from `direction`
		let forward = SCNVector3(-direction.x, -direction.y, -direction.z)
		let right = forward.cross(SCNVector3(0, 1, 0)).normalized()
		let up = right.cross(forward).normalized()

		let verticalTangent = tan(ModelCamera.fieldOfView * .pi / 360)
		let horizontalTangent = verticalTangent * aspectRatio

		var distance: CGFloat = 0
		for corner in corners {
			let offset = SCNVector3(
				corner.x - target.x,
				corner.y - target.y,
				corner.z - target.z
			)
			// Distance at which the corner reaches the edge of the field of view. Corners in front
			// of the target (positive depth) need less distance than corners behind it.
			let depth = offset.dot(forward)
			distance = max(
				distance,
				abs(offset.dot(right)) / horizontalTangent - depth,
				abs(offset.dot(up)) / verticalTangent - depth
			)
		}
		return distance * ModelCamera.margin
	}
}
