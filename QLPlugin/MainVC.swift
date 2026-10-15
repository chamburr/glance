// swiftformat:disable wrapMultilineStatementBraces
import Cocoa
import os.log
import Quartz

enum PreviewError: Error {
	case fileSizeError(path: String)
}

extension PreviewError: LocalizedError {
	var errorDescription: String? {
		switch self {
			case let .fileSizeError(path):
				return NSLocalizedString("File \(path) is too large to preview", comment: "")
		}
	}
}

class MainVC: NSViewController, QLPreviewingController {
	/// Max size of files to render
	let maxFileSize = 10_000_000 // 10 MB

	let stats = Stats()
	private var observer: LivePreviewObserver?
	private var observedURL: URL?
	private var previewGeneration = 0

	deinit { observer?.stop() }

	override var nibName: NSNib.Name? {
		NSNib.Name("MainVC")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		setUpView()
		preferredContentSize = NSSize(width: 900, height: 650)
	}

	private func setUpView() {
		// Draw border around previews, in similar style to macOS's default previews
		view.wantsLayer = true
		view.layer?.borderWidth = 1
		view.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
	}

	override func viewDidDisappear() {
		super.viewDidDisappear()
		observer?.stop()
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		observer?.start()
	}

	/// Function responsible for generating file previews. It's called for previews in Finder,
	/// Spotlight, Quick Look and any other UI elements which implement the API.
	func preparePreviewOfFile(
		at fileUrl: URL,
		completionHandler handler: @escaping (Error?) -> Void
	) {
		DispatchQueue.main.async {
			self.previewGeneration += 1
			self.observer?.stop()
			self.observer = nil
			self.observedURL = nil
			// Read information about the file to preview
			var file: File
			do {
				file = try File(url: fileUrl)
			} catch {
				os_log(
					"Could not obtain information about file %{public}s: %{public}s",
					log: Log.general,
					type: .error,
					fileUrl.path,
					error.localizedDescription
				)
				handler(error)
				return
			}

			// Skip preview if the file is too large
			let databaseExtensions = ["db", "sqlite", "sqlite3"]
			let isDatabase = databaseExtensions.contains(file.url.pathExtension.lowercased())
			let sizeLimited = !file.isDirectory && !file.isArchive && !isDatabase
			if sizeLimited, file.size > self.maxFileSize {
				// Log error and fall back to default preview (by calling the completion handler
				// with the error)
				let error = PreviewError.fileSizeError(path: file.path)
				os_log(
					"Skipping file preview: %{public}s",
					log: Log.general,
					error.localizedDescription
				)
				handler(error)
				return
			}

			// Render file preview
			os_log(
				"Generating preview for file %{public}s",
				log: Log.general,
				type: .info,
				file.path
			)
			do {
				try self.previewFile(file: file)
			} catch {
				// Log error and fall back to default preview (by calling the completion handler
				// with the error)
				os_log(
					"Could not generate preview for file %{public}s: %{public}s",
					log: Log.general,
					type: .error,
					file.path,
					error.localizedDescription
				)
				handler(error)
				return
			}

			// Hide preview loading spinner
			self.observedURL = fileUrl
			self.observer = LivePreviewObserver(url: fileUrl) { [weak self] in
				self?.refreshPreview(at: fileUrl) ?? false
			}
			self.observer?.start()
			handler(nil)
		}
	}

	private func refreshPreview(at url: URL) -> Bool {
		guard observedURL == url else {
			return false
		}
		do {
			let file = try File(url: url)
			let isDatabase = ["db", "sqlite", "sqlite3"].contains(url.pathExtension.lowercased())
			guard file.isDirectory || file.isArchive || isDatabase || file.size <= maxFileSize
			else {
				return false
			}
			try previewFile(file: file, preservingState: true)
			return true
		} catch {
			// An editor may still be replacing the file. The observer retries while the old
			// preview stays on screen; transient failures should not show a sheet.
			return false
		}
	}

	/// Generates a preview of the selected file and adds the corresponding child view controller.
	private func previewFile(file: File, preservingState: Bool = false) throws {
		// Initialize `PreviewVC` for the file type
		if let previewInitializerType = PreviewVCFactory.getPreviewInitializer(fileURL: file.url) {
			// Generate file preview
			let previewInitializer = previewInitializerType.init()
			let previewVC = try previewInitializer.createPreviewVC(file: file)

			previewGeneration += 1
			let generation = previewGeneration
			let install = { [weak self] in
				guard let self = self, self.previewGeneration == generation else {
					return
				}
				// Quick Look may reuse the controller for another file.
				for child in self.children {
					child.view.removeFromSuperview(); child.removeFromParent()
				}
				self.addChild(previewVC)
				previewVC.view.autoresizingMask = [.height, .width]
				previewVC.view.frame = self.view.bounds
				self.view.addSubview(previewVC.view)
			}
			if preservingState,
			   let old = children.first as? WebPreviewVC,
			   let replacement = previewVC as? WebPreviewVC {
				old.transferState(to: replacement, completion: install)
			} else { install() }

			os_log(
				"Preview ready: %{public}s (.%{public}s)",
				log: Log.render,
				type: .info,
				String(describing: previewInitializerType),
				file.url.pathExtension.lowercased()
			)

			// Update stats
			stats.increaseStatsCounts(fileExtension: file.url.pathExtension)
		} else {
			os_log(
				"Skipping preview for file %{public}s: File type not supported",
				log: Log.general,
				type: .info,
				file.path
			)
		}
	}
}
