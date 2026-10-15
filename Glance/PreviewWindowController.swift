// swiftformat:disable wrapMultilineStatementBraces
import Cocoa
import Quartz
import UniformTypeIdentifiers

/// The same preview controllers as the extension, without Finder's content-type arbitration.
final class PreviewWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
	let fileURL: URL
	var onClose: (() -> Void)?
	private var imageRoot: URL?
	private var imageScopeActive = false
	private var fileScopeActive = false
	private var observer: LivePreviewObserver?
	private var previewGeneration = 0

	init(fileURL: URL) throws {
		self.fileURL = fileURL
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		super.init(window: window)
		window.title = fileURL.lastPathComponent
		window.representedURL = fileURL
		window.minSize = NSSize(width: 650, height: 400)
		window.isReleasedWhenClosed = false
		window.setFrameAutosaveName("GlanceStandalonePreview")
		window.delegate = self
		fileScopeActive = fileURL.startAccessingSecurityScopedResource()
		try reload()
		observer = LivePreviewObserver(url: fileURL) { [weak self] in
			guard let self = self else {
				return false
			}
			do { try self.reload(); return true } catch { return false }
		}
		observer?.start()
		let markdownExtensions = ["md", "markdown", "mdown", "mkdn", "mkd", "rmd", "qmd"]
		if markdownExtensions.contains(fileURL.pathExtension.lowercased()) {
			let toolbar = NSToolbar(identifier: "GlancePreview")
			toolbar.delegate = self
			window.toolbar = toolbar
		}
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

	deinit {
		observer?.stop()
		if fileScopeActive { fileURL.stopAccessingSecurityScopedResource() }
		if imageScopeActive { imageRoot?.stopAccessingSecurityScopedResource() }
	}

	func reload() throws {
		let file = try File(url: fileURL)
		let database = ["db", "sqlite", "sqlite3"].contains(fileURL.pathExtension.lowercased())
		let contentType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType
		let nativeTypes: [UTType] = [.image, .pdf, .audiovisualContent, .spreadsheet, .presentation]
		let isTypeScript = fileURL.pathExtension.lowercased() == "ts" && file
			.size <= 10_000_000 && (try? file.read()) != nil
		if !isTypeScript, let contentType = contentType,
		   nativeTypes.contains(where: { contentType.conforms(to: $0) }) {
			install(NativePreviewVC(fileURL: fileURL))
			return
		}
		guard file.isDirectory || file.isArchive || database || file.size <= 10_000_000 else {
			throw FileError.fileReadError(
				path: file.path,
				message: "File exceeds the 10 MB preview limit"
			)
		}
		guard let type = PreviewVCFactory.getPreviewInitializer(fileURL: fileURL) else {
			throw FileError.fileReadError(path: file.path, message: "Unsupported file")
		}
		let preview = type.init()
		if let markdown = preview as? MarkdownPreview { markdown.imageRoot = imageRoot }
		do { install(try preview.createPreviewVC(file: file)) } catch {
			if preview is CodePreview {
				install(NativePreviewVC(fileURL: fileURL))
			} else { throw error }
		}
	}

	private func install(_ next: NSViewController) {
		previewGeneration += 1
		let generation = previewGeneration
		let replace = { [weak self] in
			guard let self = self, self.previewGeneration == generation else {
				return
			}
			self.window?.contentViewController = next
		}
		if let old = window?.contentViewController as? WebPreviewVC,
		   let nextWeb = next as? WebPreviewVC {
			old.transferState(to: nextWeb, completion: replace)
		} else { replace() }
	}

	func windowWillClose(_: Notification) {
		observer?.stop()
		previewGeneration += 1
		window?.contentViewController = nil
		onClose?()
	}

	func authorizeImageRoot(_ root: URL) throws {
		let resolved = root.resolvingSymlinksInPath().standardizedFileURL
		guard fileURL.resolvingSymlinksInPath().path.hasPrefix(resolved.path + "/") else {
			throw FileError.fileReadError(
				path: root.path,
				message: "Choose a folder containing this document"
			)
		}
		if imageScopeActive { imageRoot?.stopAccessingSecurityScopedResource() }
		imageRoot = root
		imageScopeActive = root.startAccessingSecurityScopedResource()
		try reload()
	}

	@objc
	private func chooseImageFolder() {
		guard let window = window else {
			return
		}
		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = false
		panel.directoryURL = fileURL.deletingLastPathComponent()
		panel.message = "Choose the document or project folder to allow local images. Files are only read."
		panel.beginSheetModal(for: window) { [weak self] response in
			guard response == .OK, let root = panel.url else {
				return
			}
			do { try self?.authorizeImageRoot(root) } catch { NSAlert(error: error).beginSheetModal(
				for: window,
				completionHandler: nil
			) }
		}
	}

	func toolbarAllowedItemIdentifiers(_: NSToolbar)
		-> [NSToolbarItem.Identifier] { [.init("images")] }
	func toolbarDefaultItemIdentifiers(_: NSToolbar)
		-> [NSToolbarItem.Identifier] { [.init("images")] }
	func toolbar(
		_: NSToolbar,
		itemForItemIdentifier identifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar _: Bool
	) -> NSToolbarItem? {
		let item = NSToolbarItem(itemIdentifier: identifier)
		item.label = "Allow image folder…"
		item.view = NSButton(
			title: "Allow image folder…",
			target: self,
			action: #selector(chooseImageFolder)
		)
		return item
	}
}

/// Apple-owned document/media types retain their native rendering inside the same app window.
final class NativePreviewVC: NSViewController {
	private weak var previewView: QLPreviewView?
	let fileURL: URL
	init(fileURL: URL) {
		self.fileURL = fileURL
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
	override func loadView() {
		let preview = QLPreviewView(
			frame: NSRect(x: 0, y: 0, width: 900, height: 650),
			style: .normal
		)!
		preview.previewItem = fileURL as NSURL
		view = preview
		previewView = preview
	}

	deinit { previewView?.close() }
}
