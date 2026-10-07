import Cocoa
import Foundation
import os.log
import SceneKit
import ZIPFoundation

/// Budgets that keep a malformed or hostile 3MF file from exhausting memory or time. Previews are
/// generated inside a sandboxed extension, so refusing to render a file is always better than
/// hanging or being killed.
enum ThreeMFLimits {
	/// Triangles of the whole file. SceneKit keeps three vertices per triangle in memory, and
	/// Quick Look previews are expected to be quick.
	static let maxTriangles = 1_000_000
	/// Vertices of the whole file, which a file can declare without declaring any triangle. A mesh
	/// has roughly half as many vertices as triangles, so this is generous.
	static let maxVertices = 1_500_000
	/// Decompressed size of a single model part
	static let maxPartSize = 256_000_000
	/// Decompressed size of all model parts of a file
	static let maxTotalSize = 512_000_000
	/// Model parts of a file (the production extension allows referencing arbitrarily many)
	static let maxParts = 64
	/// Nodes of the rendered scene. Objects referencing each other without forming a cycle still
	/// expand exponentially, so the triangle count of the file doesn't bound this.
	static let maxNodes = 100_000
	/// Levels of objects referencing other objects. This bounds the depth of the recursion that
	/// walks them, which `maxNodes` does not: a chain of objects each holding a single component
	/// uses one node per level. Real files nest a handful of levels deep.
	static let maxObjectDepth = 128
	/// Size of the file itself. The budgets below bound what is read out of the container, but the
	/// container's own table of contents is read before any of them applies.
	static let maxFileSize = 200_000_000
	/// Depth of the element path that is tracked while parsing. Valid 3MF nests a few levels deep;
	/// this only keeps a deeply nested file from growing the path without bound.
	static let maxElementDepth = 64
	/// Files in the container, which are indexed before anything else is read. A 3MF holds a
	/// handful of them.
	static let maxEntries = 4096
	/// Size of the relationships part, which only holds a few references
	static let maxRelationshipsSize = 1_000_000
	/// Largest coordinate that can be rendered. Geometry is handed to SceneKit as single precision
	/// floats, which overflow above ~3.4e38, and the camera divides coordinates by the tangent of
	/// its field of view. A millionth of that is still far larger than any real model.
	static let maxCoordinate = 1e12
}

enum ThreeMFError: Error {
	case archiveReadError(path: String)
	case modelNotFoundError(path: String)
	case parseError(message: String)
	case emptyModelError
	case tooLargeError(reason: String)
}

extension ThreeMFError: LocalizedError {
	var errorDescription: String? {
		switch self {
			case let .archiveReadError(path):
				return NSLocalizedString("Could not open 3MF file at path \(path)", comment: "")
			case let .modelNotFoundError(path):
				return NSLocalizedString(
					"3MF file at path \(path) does not contain a model",
					comment: ""
				)
			case let .parseError(message):
				return NSLocalizedString("Could not parse 3MF model: \(message)", comment: "")
			case .emptyModelError:
				return NSLocalizedString("3MF model does not contain any geometry", comment: "")
			case let .tooLargeError(reason):
				return NSLocalizedString(
					"3MF model is too large to preview: \(reason)",
					comment: ""
				)
		}
	}
}

/// Parses 3MF files. A 3MF file is a ZIP container holding one or more XML model parts, which
/// describe the objects of the model and their placement on the build platform.
///
/// The core specification is implemented, as well as the parts of the material and production
/// extensions that affect what the preview looks like (object colors and models split across
/// several parts). Other extensions (e.g. beam lattice) are ignored.
///
/// The contents of the file are untrusted: everything that grows with what the file declares is
/// bounded by `ThreeMFLimits`.
class ThreeMFParser: NSObject {
	/// Relationship type pointing to the model part to start parsing at
	private static let modelRelationshipType =
		"http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
	/// Path of the model part used when the container doesn't declare a relationship
	private static let defaultModelPath = "3D/3dmodel.model"
	private static let relationshipsPath = "_rels/.rels"

	private let archive: Archive

	/// Entries of the container, keyed by their normalized lowercased path. Paths inside a 3MF file
	/// are case-insensitive, and indexing them is what makes looking one up a constant-time
	/// operation.
	private var entriesByPath = [String: Entry]()

	// Parsing state
	private var model = ThreeMFModel()
	private var currentPartPath = ""
	private var isRootPart = true
	private var pendingParts = [String]()
	private var parsedParts = Set<String>()
	private var totalPartSize = 0
	private var vertexCount = 0

	/// Local names of the elements enclosing the one being parsed, the current one last
	private var elementPath = [String]()
	private var elementDepth = 0
	private var currentObjectKey: String?
	private var currentObject: ThreeMFObject?
	private var currentMesh: ThreeMFMesh?
	/// Depth of the `<mesh>` element being read, so that an element of the same name nested inside
	/// it doesn't end it
	private var currentMeshDepth: Int?
	private var currentPropertyGroupKey: String?
	private var currentPropertyColors = [NSColor]()
	/// Depth of the property group being read, for the same reason as `currentMeshDepth`
	private var currentPropertyGroupDepth: Int?
	private var parseError: ThreeMFError?

	init(fileURL: URL) throws {
		guard let archive = Archive(url: fileURL, accessMode: .read) else {
			throw ThreeMFError.archiveReadError(path: fileURL.path)
		}
		self.archive = archive
	}

	/// Indexes the entries of the container. This runs before anything is read, so the number of
	/// entries has to be bounded here rather than by one of the budgets below.
	private func buildEntryIndex() throws {
		var count = 0
		for entry in archive {
			count += 1
			guard count <= ThreeMFLimits.maxEntries else {
				throw ThreeMFError
					.tooLargeError(reason: "more than \(ThreeMFLimits.maxEntries) files")
			}
			// The first entry wins, like `Archive`'s own lookup does
			let path = ThreeMFParser.normalize(path: entry.path).lowercased()
			if entriesByPath[path] == nil {
				entriesByPath[path] = entry
			}
		}
	}

	/// Parses the model parts of the container and returns their contents.
	func parse() throws -> ThreeMFModel {
		try buildEntryIndex()
		pendingParts = [rootModelPath()]

		while let requestedPath = pendingParts.popLast() {
			guard let entry = entry(at: requestedPath) else {
				// Parts referenced by a malformed file may not exist. Only the root part is
				// required.
				if isRootPart {
					throw ThreeMFError.modelNotFoundError(path: requestedPath)
				}
				os_log(
					"Skipping missing 3MF model part %{public}s",
					log: Log.parse,
					type: .error,
					requestedPath
				)
				continue
			}

			// Parts are tracked by the path of the entry they resolve to, so that referencing the
			// same part under different spellings doesn't parse it several times
			guard !parsedParts.contains(entry.path) else {
				continue
			}
			guard parsedParts.count < ThreeMFLimits.maxParts else {
				throw ThreeMFError
					.tooLargeError(reason: "more than \(ThreeMFLimits.maxParts) model parts")
			}
			parsedParts.insert(entry.path)

			let data: Data
			do {
				data = try self.data(of: entry)
			} catch {
				// A part that is too large is not worth skipping over: the file is out of budget
				if isRootPart || error is ThreeMFError {
					throw error
				}
				os_log(
					"Skipping unreadable 3MF model part %{public}s: %{public}s",
					log: Log.parse,
					type: .error,
					entry.path,
					error.localizedDescription
				)
				continue
			}

			try parsePart(data: data, path: entry.path)
			isRootPart = false
		}

		guard model.triangleCount > 0 else {
			throw ThreeMFError.emptyModelError
		}

		// Some files (mostly exported by CAD software) don't declare a build platform. Showing
		// their objects is more useful than showing an empty preview. An explicitly empty `<build>`
		// is indistinguishable from a missing one here, which is an acceptable trade-off: a file
		// with objects but nothing on the platform is not worth an empty preview either.
		if model.buildItems.isEmpty {
			model.buildItems = topLevelObjectKeys().map {
				ThreeMFBuildItem(objectKey: $0, transform: SCNMatrix4Identity)
			}
		}

		return model
	}

	/// Keys of the objects that aren't part of another object, sorted to keep the preview stable
	/// across runs.
	private func topLevelObjectKeys() -> [String] {
		let componentKeys = Set(model.objects.values.flatMap { $0.components.map(\.objectKey) })
		return model.objects.keys.filter { !componentKeys.contains($0) }.sorted()
	}

	private func parsePart(data: Data, path: String) throws {
		currentPartPath = path
		elementPath = []
		elementDepth = 0
		currentObjectKey = nil
		currentObject = nil
		currentMesh = nil
		currentMeshDepth = nil
		currentPropertyGroupKey = nil
		currentPropertyColors = []
		currentPropertyGroupDepth = nil

		let parser = XMLParser(data: data)
		parser.delegate = self
		let success = parser.parse()

		// Budgets are global, so a part exceeding one aborts the whole preview
		if let parseError = parseError {
			throw parseError
		}
		if !success, isRootPart {
			throw ThreeMFError.parseError(
				message: parser.parserError?.localizedDescription ?? "unknown error"
			)
		}
	}

	// MARK: - Archive

	/// Returns the path of the model part referenced by the container's relationships, falling back
	/// to the conventional path.
	private func rootModelPath() -> String {
		guard let entry = entry(at: ThreeMFParser.relationshipsPath),
		      let data = try? data(of: entry, limit: ThreeMFLimits.maxRelationshipsSize),
		      let path = relationshipTarget(in: data)
		else {
			return ThreeMFParser.defaultModelPath
		}
		return ThreeMFParser.normalize(path: path)
	}

	private func relationshipTarget(in data: Data) -> String? {
		RelationshipsParser.target(of: ThreeMFParser.modelRelationshipType, in: data)
	}

	/// Reads an entry of the container into memory. The size the entry declares is metadata written
	/// by whoever created the file, so the data that is actually read has to be counted as well.
	private func data(of entry: Entry, limit: Int = ThreeMFLimits.maxPartSize) throws -> Data {
		guard entry.uncompressedSize <= UInt64(limit) else {
			throw ThreeMFError.tooLargeError(reason: "model part \(entry.path) is too large")
		}
		var budget = min(limit, ThreeMFLimits.maxTotalSize - totalPartSize)
		// An entry that decompresses to more than it says it will is malformed, so there is no
		// reason to read the rest of it
		let declaredSize = Int(entry.uncompressedSize)
		if declaredSize > 0 {
			budget = min(budget, declaredSize)
		}

		var data = Data()
		// The reservation follows what the file declares, so it is only a starting point
		data.reserveCapacity(min(budget, 8_000_000))
		// Checking the CRC32 of the entry means reading it twice, which is unnecessary for a
		// preview
		_ = try archive.extract(entry, skipCRC32: true) { chunk in
			guard data.count + chunk.count <= budget else {
				throw ThreeMFError.tooLargeError(reason: "model part \(entry.path) is too large")
			}
			data.append(chunk)
		}

		totalPartSize += data.count
		return data
	}

	private func entry(at path: String) -> Entry? {
		entriesByPath[ThreeMFParser.normalize(path: path).lowercased()]
	}

	/// Paths inside a 3MF file are absolute, while paths of ZIP entries are not.
	private static func normalize(path: String) -> String {
		path.hasPrefix("/") ? String(path.dropFirst()) : path
	}

	/// Returns the path of the entry a reference resolves to, so that resources are keyed by the
	/// part that actually holds them however the reference is spelled.
	private func canonicalPath(of path: String?) -> String {
		guard let path = path else {
			return currentPartPath
		}
		let normalized = ThreeMFParser.normalize(path: path)
		return entry(at: normalized)?.path ?? normalized
	}

	// MARK: - Parsing helpers

	/// Key uniquely identifying a resource. IDs are only unique within the model part that declares
	/// them, so the part path is part of the key.
	private func key(path: String?, id: String) -> String {
		"\(canonicalPath(of: path))#\(id)"
	}

	/// Returns an attribute of an element, ignoring the namespace prefix it may carry (e.g. the
	/// `path` attribute of the production extension).
	private static func attribute(
		_ name: String,
		of attributes: [String: String]
	) -> String? {
		if let value = attributes[name] {
			return value
		}
		// The prefix is chosen by the file, and several extensions may define an attribute with the
		// same local name, so the match is made deterministic rather than left to dictionary order
		let suffix = ":" + name
		return attributes.filter { $0.key.hasSuffix(suffix) }.min { $0.key < $1.key }?.value
	}

	/// Parses the 12 values of a 3MF transform. They are the first three columns of a 4x4 matrix in
	/// row-major order, which is the layout SceneKit uses as well.
	private static func transform(from string: String?) -> SCNMatrix4 {
		guard let values = string?
			.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
			.compactMap({ Double($0) }),
			values.count == 12,
			values.allSatisfy({ isRenderable($0) })
		else {
			return SCNMatrix4Identity
		}

		var matrix = SCNMatrix4Identity
		matrix.m11 = CGFloat(values[0])
		matrix.m12 = CGFloat(values[1])
		matrix.m13 = CGFloat(values[2])
		matrix.m21 = CGFloat(values[3])
		matrix.m22 = CGFloat(values[4])
		matrix.m23 = CGFloat(values[5])
		matrix.m31 = CGFloat(values[6])
		matrix.m32 = CGFloat(values[7])
		matrix.m33 = CGFloat(values[8])
		matrix.m41 = CGFloat(values[9])
		matrix.m42 = CGFloat(values[10])
		matrix.m43 = CGFloat(values[11])
		return matrix
	}

	/// Returns a coordinate that can be rendered. Values that are out of range reach the bounding
	/// box, the camera and finally Metal, where they turn the whole preview blank. Checking for
	/// infinity is not enough: geometry is stored as single precision floats, and the camera
	/// divides coordinates by the tangent of its field of view.
	private static func coordinate(_ value: Double) -> CGFloat {
		isRenderable(value) ? CGFloat(value) : 0
	}

	private static func isRenderable(_ value: Double) -> Bool {
		value.isFinite && abs(value) <= ThreeMFLimits.maxCoordinate
	}

	/// Parses a color in `#RRGGBB` or `#RRGGBBAA` notation.
	private static func color(from string: String?) -> NSColor? {
		guard var hex = string, hex.hasPrefix("#") else {
			return nil
		}
		hex.removeFirst()
		guard hex.count == 6 || hex.count == 8, let value = UInt32(hex, radix: 16) else {
			return nil
		}

		let hasAlpha = hex.count == 8
		let red = (value >> (hasAlpha ? 24 : 16)) & 0xFF
		let green = (value >> (hasAlpha ? 16 : 8)) & 0xFF
		let blue = (value >> (hasAlpha ? 8 : 0)) & 0xFF
		let alpha = hasAlpha ? value & 0xFF : 255

		return NSColor(
			calibratedRed: CGFloat(red) / 255,
			green: CGFloat(green) / 255,
			blue: CGFloat(blue) / 255,
			alpha: CGFloat(alpha) / 255
		)
	}

	/// Queues a model part referenced by the production extension for parsing.
	private func enqueue(partPath: String?) {
		guard let partPath = partPath else {
			return
		}
		let path = canonicalPath(of: partPath)
		guard path != currentPartPath, !parsedParts.contains(path) else {
			return
		}
		// Referencing more parts than can be parsed only wastes memory
		guard pendingParts.count < ThreeMFLimits.maxParts, !pendingParts.contains(path) else {
			return
		}
		pendingParts.append(path)
	}

	/// Whether the element being parsed is enclosed in the provided elements, innermost first.
	/// Elements of unsupported extensions (e.g. beam lattice) reuse the names of the core
	/// specification, so their contents must not be taken for the object's mesh.
	private func isEnclosed(in ancestors: String...) -> Bool {
		// Past the tracked depth the path no longer ends with the current element, so it cannot be
		// used to tell where the element sits. Valid 3MF never nests that deep.
		guard elementDepth <= ThreeMFLimits.maxElementDepth,
		      elementPath.count > ancestors.count
		else {
			return false
		}
		// The current element is last, so its ancestors are the elements before it
		let enclosing = elementPath.dropLast().suffix(ancestors.count).reversed()
		return enclosing.elementsEqual(ancestors)
	}

	/// Records that a limit was reached and stops parsing.
	private func abort(_ parser: XMLParser, reason: String) {
		parseError = .tooLargeError(reason: reason)
		parser.abortParsing()
	}
}

// MARK: - XMLParserDelegate

extension ThreeMFParser: XMLParserDelegate {
	func parser(
		_ parser: XMLParser,
		didStartElement elementName: String,
		namespaceURI _: String?,
		qualifiedName _: String?,
		attributes: [String: String] = [:]
	) {
		let localName = ThreeMFParser.localName(of: elementName)
		elementDepth += 1
		if elementDepth <= ThreeMFLimits.maxElementDepth {
			elementPath.append(localName)
		}

		switch localName {
			case "model":
				if isRootPart, let unit = ThreeMFParser.attribute("unit", of: attributes) {
					model.unit = ThreeMFUnit(rawValue: unit) ?? .millimeter
				}
			case "object":
				guard let id = ThreeMFParser.attribute("id", of: attributes) else {
					break
				}
				currentObjectKey = key(path: nil, id: id)
				var object = ThreeMFObject()
				let groupID = ThreeMFParser.attribute("pid", of: attributes)
				let index = ThreeMFParser.attribute("pindex", of: attributes).flatMap(Int.init)
				if let groupID = groupID, let index = index {
					object.propertyGroupKey = key(path: nil, id: groupID)
					object.propertyIndex = index
				}
				currentObject = object
			case "mesh":
				guard isEnclosed(in: "object") else {
					break
				}
				currentMesh = ThreeMFMesh()
				currentMeshDepth = elementDepth
			case "vertex":
				// The enclosing elements have the right names, but they also have to be the ones
				// that were accepted: a `<mesh>` nested inside the open one is ignored, and so are
				// its vertices
				guard elementDepth == (currentMeshDepth ?? .min) + 2,
				      isEnclosed(in: "vertices", "mesh"),
				      let x = ThreeMFParser.attribute("x", of: attributes).flatMap(Double.init),
				      let y = ThreeMFParser.attribute("y", of: attributes).flatMap(Double.init),
				      let z = ThreeMFParser.attribute("z", of: attributes).flatMap(Double.init)
				else {
					break
				}
				vertexCount += 1
				guard vertexCount <= ThreeMFLimits.maxVertices else {
					abort(parser, reason: "more than \(ThreeMFLimits.maxVertices) vertices")
					break
				}
				// Triangles refer to vertices by index, so a vertex is never dropped: an
				// out-of-range coordinate is replaced instead, which keeps the damage local
				currentMesh?.vertices.append(SCNVector3(
					ThreeMFParser.coordinate(x),
					ThreeMFParser.coordinate(y),
					ThreeMFParser.coordinate(z)
				))
			case "triangle":
				guard elementDepth == (currentMeshDepth ?? .min) + 2,
				      isEnclosed(in: "triangles", "mesh"),
				      let v1 = ThreeMFParser.attribute("v1", of: attributes).flatMap(Int32.init),
				      let v2 = ThreeMFParser.attribute("v2", of: attributes).flatMap(Int32.init),
				      let v3 = ThreeMFParser.attribute("v3", of: attributes).flatMap(Int32.init)
				else {
					break
				}
				model.triangleCount += 1
				guard model.triangleCount <= ThreeMFLimits.maxTriangles else {
					abort(parser, reason: "more than \(ThreeMFLimits.maxTriangles) triangles")
					break
				}
				currentMesh?.triangles.append(contentsOf: [v1, v2, v3])
			case "component":
				guard isEnclosed(in: "components", "object"),
				      let id = ThreeMFParser.attribute("objectid", of: attributes)
				else {
					break
				}
				let path = ThreeMFParser.attribute("path", of: attributes)
				enqueue(partPath: path)
				currentObject?.components.append(ThreeMFComponent(
					objectKey: key(path: path, id: id),
					transform: ThreeMFParser
						.transform(from: ThreeMFParser.attribute("transform", of: attributes))
				))
			case "item":
				guard isEnclosed(in: "build"),
				      let id = ThreeMFParser.attribute("objectid", of: attributes)
				else {
					break
				}
				let path = ThreeMFParser.attribute("path", of: attributes)
				enqueue(partPath: path)
				model.buildItems.append(ThreeMFBuildItem(
					objectKey: key(path: path, id: id),
					transform: ThreeMFParser
						.transform(from: ThreeMFParser.attribute("transform", of: attributes))
				))
			case "basematerials", "colorgroup":
				guard isEnclosed(in: "resources"),
				      let id = ThreeMFParser.attribute("id", of: attributes)
				else {
					break
				}
				currentPropertyGroupKey = key(path: nil, id: id)
				currentPropertyColors = []
				currentPropertyGroupDepth = elementDepth
			case "base":
				guard elementDepth == (currentPropertyGroupDepth ?? .min) + 1,
				      isEnclosed(in: "basematerials")
				else {
					break
				}
				currentPropertyColors.append(
					ThreeMFParser
						.color(from: ThreeMFParser.attribute("displaycolor", of: attributes))
						?? ThreeMFModel.defaultColor
				)
			case "color":
				guard elementDepth == (currentPropertyGroupDepth ?? .min) + 1,
				      isEnclosed(in: "colorgroup")
				else {
					break
				}
				currentPropertyColors.append(
					ThreeMFParser.color(from: ThreeMFParser.attribute("color", of: attributes))
						?? ThreeMFModel.defaultColor
				)
			default:
				break
		}
	}

	func parser(
		_: XMLParser,
		didEndElement elementName: String,
		namespaceURI _: String?,
		qualifiedName _: String?
	) {
		switch ThreeMFParser.localName(of: elementName) {
			// The end of an element only ends what its start began: an element of the same name
			// nested inside it (which an unsupported extension may declare) must not truncate it
			case "mesh":
				if elementDepth == currentMeshDepth {
					currentObject?.mesh = currentMesh
					currentMesh = nil
					currentMeshDepth = nil
				}
			case "object":
				if let key = currentObjectKey, let object = currentObject {
					model.objects[key] = object
				}
				currentObjectKey = nil
				currentObject = nil
				currentMesh = nil
				currentMeshDepth = nil
			case "basematerials", "colorgroup":
				if elementDepth == currentPropertyGroupDepth {
					if let key = currentPropertyGroupKey {
						model.propertyGroups[key] = currentPropertyColors
					}
					currentPropertyGroupKey = nil
					currentPropertyColors = []
					currentPropertyGroupDepth = nil
				}
			default:
				break
		}

		if elementDepth <= ThreeMFLimits.maxElementDepth, !elementPath.isEmpty {
			elementPath.removeLast()
		}
		elementDepth -= 1
	}

	/// Returns the name of an element without its namespace prefix.
	private static func localName(of elementName: String) -> String {
		guard let separatorIndex = elementName.lastIndex(of: ":") else {
			return elementName
		}
		return String(elementName[elementName.index(after: separatorIndex)...])
	}
}

// MARK: - Relationships

/// Parses the relationships part of a 3MF container, which points to the model part to start at.
private class RelationshipsParser: NSObject, XMLParserDelegate {
	private let type: String
	private var target: String?

	private init(type: String) {
		self.type = type
	}

	/// Returns the target of the first relationship with the provided type.
	static func target(of type: String, in data: Data) -> String? {
		let delegate = RelationshipsParser(type: type)
		let parser = XMLParser(data: data)
		parser.delegate = delegate
		parser.parse()
		return delegate.target
	}

	func parser(
		_: XMLParser,
		didStartElement elementName: String,
		namespaceURI _: String?,
		qualifiedName _: String?,
		attributes: [String: String] = [:]
	) {
		guard elementName.hasSuffix("Relationship"),
		      target == nil,
		      attributes["Type"] == type
		else {
			return
		}
		target = attributes["Target"]
	}
}
