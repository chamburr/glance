import Foundation

enum FileTreeError {
	case notADirectoryError(pathParts: [String.SubSequence], pathPartIndex: Int)
	case pathDepthLimitExceeded(path: String, maxDepth: Int)
	case nodeCountLimitExceeded(maxNodeCount: Int)
}

extension FileTreeError: LocalizedError {
	var errorDescription: String? {
		switch self {
			case let .notADirectoryError(pathParts, pathPartIndex):
				NSLocalizedString(
					"Cannot create file tree node with path \"\(pathParts.joined())\": \"\(pathParts[pathPartIndex])\" is not a directory",
					comment: ""
				)
			case let .pathDepthLimitExceeded(path, maxDepth):
				NSLocalizedString(
					"Cannot create file tree node with path \"\(path)\": maximum path depth of \(maxDepth) exceeded",
					comment: ""
				)
			case let .nodeCountLimitExceeded(maxNodeCount):
				NSLocalizedString(
					"Cannot create file tree node: maximum node count of \(maxNodeCount) exceeded",
					comment: ""
				)
		}
	}
}

/// Data structure for representing a single file/directory in a tree. The class is designed to be
/// used in an `NSOutlineView`, which is why the `@objc` attributes are required.
class FileTreeNode: NSObject {
	/// Name of the file (without path information), e.g. `"myfile.txt"`
	@objc let name: String
	/// File size in bytes
	@objc let size: Int
	@objc let isDirectory: Bool
	@objc var dateModified: Date?
	/// Child nodes of a directory
	@objc var children = [String: FileTreeNode]()

	/// Number of child nodes (required for rendering the tree in an `NSOutlineView`)
	@objc var childrenCount: Int { children.values.count }
	/// List of child nodes (required for rendering the tree in an `NSOutlineView`)
	@objc var childrenList: [FileTreeNode] { Array(children.values) }
	/// Whether the node has any children (required for rendering the tree in an `NSOutlineView`)
	@objc var hasChildren: Bool { !children.isEmpty }
	/// Whether the node is a leaf (has no children) — used by `NSTreeController`'s `leafKeyPath`
	@objc var isLeaf: Bool { children.isEmpty }

	convenience init(name: String, size: Int, isDirectory: Bool) {
		self.init(name: name, size: size, isDirectory: isDirectory, dateModified: nil)
	}

	init(name: String, size: Int, isDirectory: Bool, dateModified: Date?) {
		self.name = name
		self.size = size
		self.isDirectory = isDirectory
		self.dateModified = dateModified
	}
}

/// Data structure for representing a tree of files and directories. This class stores the root node
/// and provides functionality to insert new nodes.
class FileTree {
	static let defaultMaxPathDepth = 128
	static let defaultMaxNodeCount = 50_000

	var root = FileTreeNode(name: "Root", size: 0, isDirectory: true, dateModified: Date())
	private let maxPathDepth: Int
	private let maxNodeCount: Int
	private var nodeCount = 1

	init(
		maxPathDepth: Int = FileTree.defaultMaxPathDepth,
		maxNodeCount: Int = FileTree.defaultMaxNodeCount
	) {
		self.maxPathDepth = max(1, maxPathDepth)
		self.maxNodeCount = max(1, maxNodeCount)
	}

	/// Parses the provided file/directory's path and creates a new `FileTreeNode` at the correct
	/// position in the tree. If a file/directory's parent directory doesn't exist yet, it will
	/// be created (with `dateModified` set to `nil`).
	func addNode(path: String, isDirectory: Bool, size: Int, dateModified: Date?) throws {
		let pathParts = path.split(separator: "/", omittingEmptySubsequences: true)
		guard !pathParts.isEmpty else {
			return
		}
		guard pathParts.count <= maxPathDepth else {
			throw FileTreeError.pathDepthLimitExceeded(path: path, maxDepth: maxPathDepth)
		}

		var parentNode = root
		for (pathPartIndex, pathPart) in pathParts.enumerated() {
			let isLastPathPart = pathPartIndex == pathParts.count - 1
			let name = String(pathPart)
			let currentNode = parentNode.children[name]

			if isLastPathPart {
				if let currentNode {
					// Node already exists (i.e. directory has been created implicitly in a previous
					// function call): Update the directory node with the missing `dateModified` info
					currentNode.dateModified = dateModified
				} else {
					_ = try createNode(
						parentNode: parentNode,
						name: name,
						size: size,
						isDirectory: isDirectory,
						dateModified: dateModified
					)
				}
			} else {
				if let currentNode {
					guard currentNode.isDirectory else {
						throw FileTreeError.notADirectoryError(
							pathParts: pathParts,
							pathPartIndex: pathPartIndex
						)
					}
					parentNode = currentNode
				} else {
					parentNode = try createNode(
						parentNode: parentNode,
						name: name,
						size: 0,
						isDirectory: true,
						dateModified: nil
					)
				}
			}
		}
	}

	private func createNode(
		parentNode: FileTreeNode,
		name: String,
		size: Int,
		isDirectory: Bool,
		dateModified: Date?
	) throws -> FileTreeNode {
		guard nodeCount < maxNodeCount else {
			throw FileTreeError.nodeCountLimitExceeded(maxNodeCount: maxNodeCount)
		}
		let node = FileTreeNode(
			name: name,
			size: size,
			isDirectory: isDirectory,
			dateModified: dateModified
		)
		parentNode.children[name] = node
		nodeCount += 1
		return node
	}
}
