import Foundation
import os.log

class DirectoryPreview: Preview {
	let fileManager = FileManager.default

	/// Max number of items to include in the tree to avoid performance issues.
	let maxItems = 500
	/// Max recursion depth.
	let maxDepth = 5

	required init() {}

	/// Directories inside temporary extraction paths (e.g. from ZIP browsing in Finder)
	/// should not be previewed by our plugin.
	private func isTemporaryPath(_ path: String) -> Bool {
		return path.hasPrefix("/private/var/folders/")
			|| path.hasPrefix("/var/folders/")
			|| path.hasPrefix("/tmp/")
			|| path.hasPrefix("/private/tmp/")
	}

	func createPreviewVC(file: File) throws -> PreviewVC {
		if isTemporaryPath(file.path) {
			throw PreviewError.fileSizeError(path: file.path)
		}

		let fileTree = FileTree()
		var itemCount = 0
		scanDirectory(url: file.url, fileTree: fileTree, basePath: file.url.path, depth: 0, itemCount: &itemCount)

		let childrenCount = countItems(nodes: fileTree.root.childrenList)
		let labelText = "\(childrenCount) items"

		return OutlinePreviewVC(rootNodes: fileTree.root.childrenList, labelText: labelText, expandAll: true)
	}

	private func scanDirectory(url: URL, fileTree: FileTree, basePath: String, depth: Int, itemCount: inout Int) {
		guard depth < maxDepth, itemCount < maxItems else { return }

		let contents: [URL]
		do {
			contents = try fileManager.contentsOfDirectory(
				at: url,
				includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
				options: [.skipsHiddenFiles]
			)
		} catch {
			os_log(
				"Could not read directory %{public}s: %{public}s",
				log: Log.general,
				type: .error,
				url.path,
				error.localizedDescription
			)
			return
		}

		for itemURL in contents {
			guard itemCount < maxItems else { return }

			let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
			let isDir = resourceValues?.isDirectory ?? false
			let size = resourceValues?.fileSize ?? 0
			let dateModified = resourceValues?.contentModificationDate

			// Build relative path from the base directory
			let relativePath = String(itemURL.path.dropFirst(basePath.count + 1))

			do {
				try fileTree.addNode(
					path: relativePath,
					isDirectory: isDir,
					size: size,
					dateModified: dateModified
				)
				itemCount += 1
			} catch {
				os_log("%{public}s", log: Log.parse, type: .error, error.localizedDescription)
			}

			if isDir {
				scanDirectory(url: itemURL, fileTree: fileTree, basePath: basePath, depth: depth + 1, itemCount: &itemCount)
			}
		}
	}

	private func countItems(nodes: [FileTreeNode]) -> Int {
		var count = nodes.count
		for node in nodes where node.isDirectory {
			count += countItems(nodes: node.childrenList)
		}
		return count
	}
}
