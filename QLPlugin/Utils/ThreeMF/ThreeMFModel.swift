import Cocoa
import os.log
import SceneKit

/// Unit of measurement a 3MF model is expressed in.
enum ThreeMFUnit: String {
	case micron
	case millimeter
	case centimeter
	case inch
	case foot
	case meter

	/// Length of one unit in millimeters.
	var millimeters: CGFloat {
		switch self {
			case .micron:
				return 0.001
			case .millimeter:
				return 1
			case .centimeter:
				return 10
			case .inch:
				return 25.4
			case .foot:
				return 304.8
			case .meter:
				return 1000
		}
	}
}

/// Triangle mesh of a 3MF object. Triangles are stored as a flat list of indices into `vertices`.
struct ThreeMFMesh {
	var vertices = [SCNVector3]()
	var triangles = [Int32]()

	var triangleCount: Int {
		triangles.count / 3
	}
}

/// Reference from an object to another object, with the transform to apply to it.
struct ThreeMFComponent {
	let objectKey: String
	let transform: SCNMatrix4
}

/// Object of a 3MF model. It either contains a mesh, or is an assembly of other objects.
struct ThreeMFObject {
	var mesh: ThreeMFMesh?
	var components = [ThreeMFComponent]()
	/// Property group the object's color is taken from (`pid` attribute)
	var propertyGroupKey: String?
	/// Index of the object's color within its property group (`pindex` attribute)
	var propertyIndex: Int?
}

/// Object placed on the build platform, with the transform to apply to it.
struct ThreeMFBuildItem {
	let objectKey: String
	let transform: SCNMatrix4
}

/// Contents of a 3MF file. Objects and property groups are keyed by `<part path>#<id>`, because IDs
/// are only unique within the model part they are declared in (production extension).
struct ThreeMFModel {
	var unit = ThreeMFUnit.millimeter
	var objects = [String: ThreeMFObject]()
	var buildItems = [ThreeMFBuildItem]()
	/// Colors declared by `<basematerials>` and `<colorgroup>` resources
	var propertyGroups = [String: [NSColor]]()
	var triangleCount = 0
}

/// Rendered 3MF model, together with the metadata shown next to the preview.
struct ThreeMFScene {
	let scene: SCNScene
	/// Camera to position once the size of the view is known
	let camera: ModelCamera
	/// Size of the model's bounding box in millimeters
	let dimensions: SCNVector3
	let triangleCount: Int
}

/// Axis-aligned bounding box.
private struct Bounds {
	var min: SCNVector3
	var max: SCNVector3

	init(min: SCNVector3, max: SCNVector3) {
		self.min = min
		self.max = max
	}

	init?(vertices: [SCNVector3]) {
		guard let first = vertices.first else {
			return nil
		}
		min = first
		max = first
		for vertex in vertices.dropFirst() {
			min.x = Swift.min(min.x, vertex.x)
			min.y = Swift.min(min.y, vertex.y)
			min.z = Swift.min(min.z, vertex.z)
			max.x = Swift.max(max.x, vertex.x)
			max.y = Swift.max(max.y, vertex.y)
			max.z = Swift.max(max.z, vertex.z)
		}
	}

	var center: SCNVector3 {
		SCNVector3((min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2)
	}

	var size: SCNVector3 {
		SCNVector3(max.x - min.x, max.y - min.y, max.z - min.z)
	}

	/// Whether the box can be measured and framed. Coordinates are checked as they are read, but
	/// transforms compose multiplicatively up the tree, so a chain of individually harmless scales
	/// still lands the box out of range. Checking for infinity is not enough here either: SceneKit
	/// stores node positions as single precision floats.
	var isRenderable: Bool {
		[min.x, min.y, min.z, max.x, max.y, max.z].allSatisfy {
			$0.isFinite && abs($0) <= CGFloat(ThreeMFLimits.maxCoordinate)
		}
	}

	/// Radius of the sphere containing the bounding box.
	var radius: CGFloat {
		let size = self.size
		return sqrt(size.x * size.x + size.y * size.y + size.z * size.z) / 2
	}

	func union(_ other: Bounds) -> Bounds {
		Bounds(
			min: SCNVector3(
				Swift.min(min.x, other.min.x),
				Swift.min(min.y, other.min.y),
				Swift.min(min.z, other.min.z)
			),
			max: SCNVector3(
				Swift.max(max.x, other.max.x),
				Swift.max(max.y, other.max.y),
				Swift.max(max.z, other.max.z)
			)
		)
	}

	var corners: [SCNVector3] {
		var corners = [SCNVector3]()
		for x in [min.x, max.x] {
			for y in [min.y, max.y] {
				for depth in [min.z, max.z] {
					corners.append(SCNVector3(x, y, depth))
				}
			}
		}
		return corners
	}

	/// Returns the bounding box of this box's eight corners after applying the transform.
	func transformed(by transform: SCNMatrix4) -> Bounds {
		// The array is never empty, so the initializer cannot fail
		Bounds(vertices: corners.map { $0.transformed(by: transform) })!
	}
}

extension ThreeMFModel {
	/// Color used for objects without a material
	static let defaultColor = NSColor(calibratedRed: 0.65, green: 0.68, blue: 0.73, alpha: 1)

	/// Builds a SceneKit scene containing all objects placed on the build platform.
	func buildScene() throws -> ThreeMFScene {
		var geometries = [String: SCNGeometry]()
		var boundsCache = [String: Bounds?]()
		var nodeCount = 0
		var renderedTriangles = 0

		// Objects of the build platform, in the model's own coordinate system
		let contentNode = SCNNode()
		var contentBounds: Bounds?

		for item in buildItems {
			guard let node = try makeNode(
				objectKey: item.objectKey,
				geometries: &geometries,
				nodeCount: &nodeCount,
				renderedTriangles: &renderedTriangles
			) else {
				continue
			}
			node.transform = item.transform
			contentNode.addChildNode(node)

			var hitCycle = false
			let itemBounds = localBounds(
				objectKey: item.objectKey,
				cache: &boundsCache,
				hitCycle: &hitCycle
			)
			if let bounds = itemBounds?.transformed(by: item.transform) {
				contentBounds = contentBounds?.union(bounds) ?? bounds
			}
		}

		// Every node that is kept holds geometry somewhere below it, so an empty platform means
		// there is nothing to show (e.g. a file whose objects only reference each other)
		guard !contentNode.childNodes.isEmpty else {
			throw ThreeMFError.emptyModelError
		}

		// Rather than measuring and framing the model with values that overflowed, fall back to
		// showing it from a default distance
		if contentBounds?.isRenderable == false {
			os_log("Ignoring 3MF bounding box that is out of range", log: Log.render, type: .error)
			contentBounds = nil
		}

		// 3MF models are Z-up, SceneKit is Y-up
		let rootNode = SCNNode()
		rootNode.transform = SCNMatrix4MakeRotation(-.pi / 2, 1, 0, 0)
		rootNode.addChildNode(contentNode)

		let scene = SCNScene()
		scene.rootNode.addChildNode(rootNode)
		let camera = makeCamera(bounds: contentBounds)
		scene.rootNode.addChildNode(camera.node)
		addLights(to: scene)

		let size = contentBounds?.size ?? SCNVector3Zero
		let scale = unit.millimeters
		return ThreeMFScene(
			scene: scene,
			camera: camera,
			dimensions: SCNVector3(size.x * scale, size.y * scale, size.z * scale),
			triangleCount: renderedTriangles
		)
	}

	/// Builds the node for an object, recursing into its components. `visited` guards against
	/// objects referencing each other in a cycle, which the 3MF specification forbids, and
	/// `nodeCount` against objects that reference each other so often that the scene explodes even
	/// though the file holds barely any geometry.
	private func makeNode(
		objectKey: String,
		geometries: inout [String: SCNGeometry],
		nodeCount: inout Int,
		renderedTriangles: inout Int,
		visited: Set<String> = [],
		depth: Int = 0
	) throws -> SCNNode? {
		guard !visited.contains(objectKey), let object = objects[objectKey] else {
			return nil
		}
		// A chain of objects each referencing a single other object stays well within `maxNodes`
		// while recursing once per level, which would exhaust the stack
		guard depth < ThreeMFLimits.maxObjectDepth else {
			throw ThreeMFError.tooLargeError(
				reason: "objects nested more than \(ThreeMFLimits.maxObjectDepth) levels deep"
			)
		}
		var visited = visited
		visited.insert(objectKey)

		nodeCount += 1
		guard nodeCount <= ThreeMFLimits.maxNodes else {
			throw ThreeMFError
				.tooLargeError(reason: "more than \(ThreeMFLimits.maxNodes) objects to place")
		}

		let node = SCNNode()

		if let mesh = object.mesh, mesh.triangleCount > 0 {
			if let geometry = geometries[objectKey] {
				node.geometry = geometry
			} else if let geometry = ThreeMFModel.makeGeometry(
				mesh: mesh,
				color: color(of: object)
			) {
				geometries[objectKey] = geometry
				node.geometry = geometry
			}
			// Triangles the file declares but that couldn't be rendered (e.g. because they refer
			// to vertices that don't exist) are not counted
			renderedTriangles += node.geometry?.elements.first?.primitiveCount ?? 0
		}

		for component in object.components {
			guard let childNode = try makeNode(
				objectKey: component.objectKey,
				geometries: &geometries,
				nodeCount: &nodeCount,
				renderedTriangles: &renderedTriangles,
				visited: visited,
				depth: depth + 1
			) else {
				continue
			}
			childNode.transform = component.transform
			node.addChildNode(childNode)
		}

		return node.geometry == nil && node.childNodes.isEmpty ? nil : node
	}

	/// Bounding box of an object in its own coordinate system, including its components.
	/// `hitCycle` reports whether the traversal was cut short by the cycle guard, in which case the
	/// result is incomplete and must not be cached.
	private func localBounds(
		objectKey: String,
		cache: inout [String: Bounds?],
		hitCycle: inout Bool,
		visited: Set<String> = [],
		depth: Int = 0
	) -> Bounds? {
		if let cached = cache[objectKey] {
			return cached
		}
		// This walks the same graph as `makeNode` and needs the same bound on its recursion. The
		// result is incomplete when the walk stops early, so it is reported like a cycle.
		guard depth < ThreeMFLimits.maxObjectDepth else {
			hitCycle = true
			return nil
		}
		guard !visited.contains(objectKey) else {
			hitCycle = true
			return nil
		}
		guard let object = objects[objectKey] else {
			return nil
		}
		var visited = visited
		visited.insert(objectKey)

		var truncated = false
		var bounds = object.mesh.flatMap { Bounds(vertices: $0.vertices) }
		for component in object.components {
			guard let componentBounds = localBounds(
				objectKey: component.objectKey,
				cache: &cache,
				hitCycle: &truncated,
				visited: visited,
				depth: depth + 1
			)?.transformed(by: component.transform) else {
				continue
			}
			bounds = bounds?.union(componentBounds) ?? componentBounds
		}

		if truncated {
			hitCycle = true
		} else {
			cache[objectKey] = bounds
		}
		return bounds
	}

	private func color(of object: ThreeMFObject) -> NSColor {
		guard let groupKey = object.propertyGroupKey,
		      let index = object.propertyIndex,
		      let colors = propertyGroups[groupKey],
		      colors.indices.contains(index)
		else {
			return ThreeMFModel.defaultColor
		}
		return colors[index]
	}

	/// Converts a mesh to a SceneKit geometry. Vertices are duplicated for every triangle so that
	/// each face gets its own normal: 3MF meshes share vertices between faces, and averaging their
	/// normals would make hard edges look rounded.
	private static func makeGeometry(mesh: ThreeMFMesh, color: NSColor) -> SCNGeometry? {
		// Coordinates are kept as single precision floats: large models have millions of them, and
		// SceneKit converts them to floats when rendering anyway
		var positions = [Float]()
		var normals = [Float]()
		positions.reserveCapacity(mesh.triangles.count * 3)
		normals.reserveCapacity(mesh.triangles.count * 3)
		var vertexCount = 0

		for index in stride(from: 0, to: mesh.triangles.count, by: 3) {
			let indices = [
				Int(mesh.triangles[index]),
				Int(mesh.triangles[index + 1]),
				Int(mesh.triangles[index + 2]),
			]
			// Skip triangles referencing vertices that don't exist
			guard indices.allSatisfy({ mesh.vertices.indices.contains($0) }) else {
				continue
			}

			let vertices = indices.map { mesh.vertices[$0] }
			let normal = faceNormal(vertices[0], vertices[1], vertices[2])
			for vertex in vertices {
				positions.append(contentsOf: [Float(vertex.x), Float(vertex.y), Float(vertex.z)])
				normals.append(contentsOf: [Float(normal.x), Float(normal.y), Float(normal.z)])
			}
			vertexCount += 3
		}

		guard vertexCount > 0 else {
			return nil
		}

		let element = SCNGeometryElement(
			indices: [Int32](0 ..< Int32(vertexCount)),
			primitiveType: .triangles
		)
		let geometry = SCNGeometry(
			sources: [
				makeSource(components: positions, count: vertexCount, semantic: .vertex),
				makeSource(components: normals, count: vertexCount, semantic: .normal),
			],
			elements: [element]
		)

		let material = SCNMaterial()
		material.lightingModel = .physicallyBased
		material.diffuse.contents = color
		material.metalness.contents = 0.0
		material.roughness.contents = 0.55
		// Meshes with inconsistently oriented triangles are common, so render both sides
		material.isDoubleSided = true
		geometry.materials = [material]

		return geometry
	}

	/// Builds a geometry source from a flat list of three-dimensional vectors.
	private static func makeSource(
		components: [Float],
		count: Int,
		semantic: SCNGeometrySource.Semantic
	) -> SCNGeometrySource {
		let data = components.withUnsafeBufferPointer { Data(buffer: $0) }
		return SCNGeometrySource(
			data: data,
			semantic: semantic,
			vectorCount: count,
			usesFloatComponents: true,
			componentsPerVector: 3,
			bytesPerComponent: MemoryLayout<Float>.size,
			dataOffset: 0,
			dataStride: MemoryLayout<Float>.size * 3
		)
	}

	private static func faceNormal(
		_ first: SCNVector3,
		_ second: SCNVector3,
		_ third: SCNVector3
	) -> SCNVector3 {
		let edge1 = SCNVector3(second.x - first.x, second.y - first.y, second.z - first.z)
		let edge2 = SCNVector3(third.x - first.x, third.y - first.y, third.z - first.z)
		return edge1.cross(edge2).normalized()
	}

	/// Builds the camera showing the model. It is positioned by `ModelCamera` once the size of the
	/// view is known.
	private func makeCamera(bounds: Bounds?) -> ModelCamera {
		guard let bounds = bounds, bounds.radius > 0 else {
			return ModelCamera(target: SCNVector3Zero, corners: [], radius: 0)
		}

		// Convert the bounding box from the model's Z-up system to SceneKit's Y-up system
		let center = bounds.center
		return ModelCamera(
			target: SCNVector3(center.x, center.z, -center.y),
			corners: bounds.corners.map { SCNVector3($0.x, $0.z, -$0.y) },
			radius: bounds.radius
		)
	}

	/// Adds ambient light, so that the sides facing away from the camera don't turn black. The
	/// remaining lighting is provided by `SCNView.autoenablesDefaultLighting`.
	private func addLights(to scene: SCNScene) {
		let light = SCNLight()
		light.type = .ambient
		light.color = NSColor(calibratedWhite: 0.45, alpha: 1)

		let lightNode = SCNNode()
		lightNode.light = light
		scene.rootNode.addChildNode(lightNode)
	}
}
