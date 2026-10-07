import Cocoa
import SceneKit

/// View controller for previewing 3D models. The model can be rotated, panned and zoomed.
class ModelPreviewVC: NSViewController, PreviewVC {
	private static let labelPadding: CGFloat = 10

	private let scene: SCNScene
	private let camera: ModelCamera
	private let labelText: String?

	/// The camera is only framed once, so that resizing the preview doesn't undo the rotating and
	/// zooming the user may have done
	private var hasFramedCamera = false

	required convenience init(scene: SCNScene, camera: ModelCamera, labelText: String?) {
		self.init(
			nibName: nil,
			bundle: nil,
			scene: scene,
			camera: camera,
			labelText: labelText
		)
	}

	init(
		nibName nibNameOrNil: NSNib.Name?,
		bundle nibBundleOrNil: Bundle?,
		scene: SCNScene,
		camera: ModelCamera,
		labelText: String?
	) {
		self.scene = scene
		self.camera = camera
		self.labelText = labelText
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		// The view is resized by whoever displays it, but starting from a non-empty size avoids
		// laying out the preview at zero size
		view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		setUpView()
	}

	/// The camera can only be positioned once the size of the view is known, because how far the
	/// model has to be to fit the view depends on the view's aspect ratio.
	override func viewDidLayout() {
		super.viewDidLayout()

		guard !hasFramedCamera, view.bounds.height > 0 else {
			return
		}
		camera.frame(aspectRatio: view.bounds.width / view.bounds.height)
		hasFramedCamera = true
	}

	private func setUpView() {
		let sceneView = SCNView()
		sceneView.scene = scene
		sceneView.pointOfView = camera.node
		sceneView.allowsCameraControl = true
		sceneView.autoenablesDefaultLighting = true
		sceneView.antialiasingMode = .multisampling4X
		// Let the preview's background show through, so it matches the system appearance
		sceneView.backgroundColor = .clear
		sceneView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(sceneView)

		NSLayoutConstraint.activate([
			sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			sceneView.topAnchor.constraint(equalTo: view.topAnchor),
			sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])

		guard let labelText = labelText else {
			return
		}

		let label = NSTextField(labelWithString: labelText)
		label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		label.textColor = .secondaryLabelColor
		label.lineBreakMode = .byTruncatingTail
		label.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(label)

		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(
				equalTo: view.leadingAnchor,
				constant: ModelPreviewVC.labelPadding
			),
			// The label is built from the model's own measurements, so it is kept inside the view
			// however long they turn out to be
			label.trailingAnchor.constraint(
				lessThanOrEqualTo: view.trailingAnchor,
				constant: -ModelPreviewVC.labelPadding
			),
			label.bottomAnchor.constraint(
				equalTo: view.bottomAnchor,
				constant: -ModelPreviewVC.labelPadding
			),
		])
	}
}
