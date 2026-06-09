import Cocoa
import Quartz

enum PreviewError: Error {
	case fileSizeError(path: String)
}

extension PreviewError: LocalizedError {
	var errorDescription: String? {
		switch self {
			case let .fileSizeError(path):
				NSLocalizedString("File \(path) is too large to preview", comment: "")
		}
	}
}

class MainVC: NSViewController, QLPreviewingController {
	/// Max size of files to render
	let maxFileSize = 10_000_000 // 10 MB

	/// Bundle ID of the containing app. When the app isn't running, the QL extension
	/// declines to preview and lets macOS fall back to the system handler.
	private static let containingAppBundleID = "com.chamburr.Glance"

	let stats = Stats()

	override var nibName: NSNib.Name? {
		NSNib.Name("MainVC")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		setUpView()
	}

	private func setUpView() {
		// Draw border around previews, in similar style to macOS's default previews
		view.wantsLayer = true
		view.layer?.borderWidth = 1
		view.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
	}

	/// Function responsible for generating file previews. It's called for previews in Finder,
	/// Spotlight, Quick Look and any other UI elements which implement the API.
	func preparePreviewOfFile(
		at fileUrl: URL,
		completionHandler handler: @escaping (Error?) -> Void
	) {
		DispatchQueue.main.async {
			// Only preview files when the containing app is running
			if NSRunningApplication.runningApplications(
				withBundleIdentifier: Self.containingAppBundleID
			).isEmpty {
				Log.general.info("Glance app is not running, declining preview")
				let error = NSError(
					domain: "com.chamburr.Glance.QLPlugin",
					code: 1,
					userInfo: [NSLocalizedDescriptionKey: "Glance app is not running"]
				)
				handler(error)
				return
			}

			// Read information about the file to preview
			var file: File
			do {
				file = try File(url: fileUrl)
			} catch {
				Log.general.error(
					"Could not obtain information about file \(fileUrl.path, privacy: .private): \(error.localizedDescription, privacy: .private)"
				)
				handler(error)
				return
			}

			// Skip preview if the file is too large
			if !file.isDirectory, !file.isArchive, file.size > self.maxFileSize {
				// Log error and fall back to default preview (by calling the completion handler
				// with the error)
				let error = PreviewError.fileSizeError(path: file.path)
				Log.general
					.error("Skipping file preview: \(error.localizedDescription, privacy: .private)")
				handler(error)
				return
			}

			// Render file preview
			Log.general.info("Generating preview for file \(file.path, privacy: .private)")
			do {
				try self.previewFile(file: file)
			} catch {
				// Log error and fall back to default preview (by calling the completion handler
				// with the error)
				Log.general.error(
					"Could not generate preview for file \(file.path, privacy: .private): \(error.localizedDescription, privacy: .private)"
				)
				handler(error)
				return
			}

			// Hide preview loading spinner
			handler(nil)
		}
	}

	/// Generates a preview of the selected file and adds the corresponding child view controller.
	private func previewFile(file: File) throws {
		// Initialize `PreviewVC` for the file type
		if let previewInitializerType = PreviewVCFactory.getPreviewInitializer(fileURL: file.url) {
			// Generate file preview
			let previewInitializer = previewInitializerType.init()
			let previewVC = try previewInitializer.createPreviewVC(file: file)

			// Add `PreviewVC` as a child view controller
			addChild(previewVC)
			previewVC.view.autoresizingMask = [.height, .width]
			previewVC.view.frame = view.bounds
			view.addSubview(previewVC.view)

			// Update stats
			stats.increaseStatsCounts(fileExtension: file.url.pathExtension)
		} else {
			Log.general.info(
				"Skipping preview for file \(file.path, privacy: .private): File type not supported"
			)
		}
	}
}
