import Foundation
import SceneKit

extension SCNVector3 {
	func dot(_ other: SCNVector3) -> CGFloat {
		x * other.x + y * other.y + z * other.z
	}

	func cross(_ other: SCNVector3) -> SCNVector3 {
		SCNVector3(
			y * other.z - z * other.y,
			z * other.x - x * other.z,
			x * other.y - y * other.x
		)
	}

	/// Returns the vector scaled to a length of one, or the unit vector along the z-axis if the
	/// vector has no length.
	func normalized() -> SCNVector3 {
		let length = sqrt(x * x + y * y + z * z)
		guard length > 0 else {
			return SCNVector3(0, 0, 1)
		}
		return SCNVector3(x / length, y / length, z / length)
	}

	/// Applies a transform to the point. SceneKit stores the translation in the fourth row of a
	/// matrix, so points are multiplied as row vectors.
	func transformed(by matrix: SCNMatrix4) -> SCNVector3 {
		SCNVector3(
			x * matrix.m11 + y * matrix.m21 + z * matrix.m31 + matrix.m41,
			x * matrix.m12 + y * matrix.m22 + z * matrix.m32 + matrix.m42,
			x * matrix.m13 + y * matrix.m23 + z * matrix.m33 + matrix.m43
		)
	}
}
