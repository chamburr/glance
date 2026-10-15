// swiftformat:disable wrapMultilineStatementBraces
import Cocoa
import os.log
import WebKit

/// Only bundled assets are served. Previews never fetch scripts, images or fonts from the network.
final class PreviewAssetHandler: NSObject, WKURLSchemeHandler {
	func webView(_: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
		guard let name = urlSchemeTask.request.url?.lastPathComponent,
		      let resource = Bundle.main.resourceURL?.appendingPathComponent(name),
		      let data = try? Data(contentsOf: resource)
		else {
			urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
			return
		}
		let types = [
			"css": "text/css",
			"js": "text/javascript",
			"woff2": "font/woff2",
			"woff": "font/woff",
			"ttf": "font/ttf",
		]
		guard types[resource.pathExtension] != nil else {
			urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
			return
		}
		let response = URLResponse(
			url: urlSchemeTask.request.url!,
			mimeType: types[resource.pathExtension] ??
				"application/octet-stream",
			expectedContentLength: data.count,
			textEncodingName: "utf-8"
		)
		urlSchemeTask.didReceive(response)
		urlSchemeTask.didReceive(data)
		urlSchemeTask.didFinish()
	}

	func webView(_: WKWebView, stop _: WKURLSchemeTask) {}
}

/// Reports rendering completion from inside the actual sandboxed extension, without logging
/// content.
final class PreviewReadyHandler: NSObject, WKScriptMessageHandler {
	var onReady: (() -> Void)?

	func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
		guard let counts = message.body as? [String: Int] else {
			return
		}
		os_log(
			"Local preview rendered: headings=%d diagrams=%d math=%d text=%d",
			log: Log.render,
			type: .info,
			counts["headings", default: 0],
			counts["diagrams", default: 0],
			counts["math", default: 0],
			counts["text", default: 0]
		)
		onReady?()
	}
}

/// Polls metadata only while a preview is alive. Looking up the path on each tick also detects
/// editors that save to a temporary file and atomically replace the original inode.
final class LivePreviewObserver {
	private struct Signature: Equatable {
		let inode: UInt64
		let size: UInt64
		let modified: Date
	}

	private let url: URL
	private let onChange: () -> Bool
	private var timer: Timer?
	private var accepted: Signature?
	private var candidate: Signature?
	private var retryAfter = Date.distantPast

	init(url: URL, onChange: @escaping () -> Bool) {
		self.url = url
		self.onChange = onChange
	}

	func start() {
		guard timer == nil else {
			return
		}
		if accepted == nil { accepted = signature() }
		candidate = nil
		let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
			self?.tick()
		}
		self.timer = timer
		RunLoop.main.add(timer, forMode: .common)
	}

	func stop() {
		timer?.invalidate()
		timer = nil
		candidate = nil
	}

	deinit { stop() }

	private func signature() -> Signature? {
		guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
		      let inode = attributes[.systemFileNumber] as? NSNumber,
		      let size = attributes[.size] as? NSNumber,
		      let modified = attributes[.modificationDate] as? Date else { return nil }
		return Signature(inode: inode.uint64Value, size: size.uint64Value, modified: modified)
	}

	private func tick() {
		// A missing path is normal during an atomic save. Keep showing the last good preview.
		guard let current = signature() else {
			candidate = nil
			return
		}
		guard current != accepted else {
			candidate = nil
			return
		}
		guard current == candidate else {
			candidate = current
			return
		}
		guard Date() >= retryAfter else {
			return
		}
		if onChange() {
			accepted = current
		} else {
			// Retry transient read failures without logging or rebuilding on every timer tick.
			retryAfter = Date().addingTimeInterval(2)
		}
	}
}

class WebPreviewVC: NSViewController, PreviewVC, WKNavigationDelegate {
	private struct ScrollState {
		let x: Double
		let y: Double
		let contents: Bool
		let search: String
	}

	let html: String
	private let stylesheets: [Stylesheet]
	private let scripts: [Script]
	private let source: String?
	private let preferences = UserDefaults.standard
	private var searchField: NSSearchField!
	private(set) var webView: WKWebView!
	private var readyHandler: PreviewReadyHandler?
	private var pendingScrollState: ScrollState?

	required convenience init(
		html: String,
		stylesheets: [Stylesheet] = [],
		scripts: [Script] = [],
		source: String? = nil
	) {
		self.init(
			nibName: nil,
			bundle: nil,
			html: html,
			stylesheets: stylesheets,
			scripts: scripts,
			source: source
		)
	}

	init(
		nibName nibNameOrNil: NSNib.Name?,
		bundle nibBundleOrNil: Bundle?,
		html: String,
		stylesheets: [Stylesheet] = [],
		scripts: [Script] = [],
		source: String? = nil
	) {
		self.html = html
		self.source = source
		self.stylesheets = stylesheets
		self.scripts = scripts
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		let readyHandler = PreviewReadyHandler()
		readyHandler.onReady = { [weak self] in self?.restoreScroll() }
		self.readyHandler = readyHandler
		configuration.userContentController.add(readyHandler, name: "glanceReady")
		configuration.setURLSchemeHandler(PreviewAssetHandler(), forURLScheme: "glance-resource")
		webView = WKWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = self
		webView.allowsMagnification = true
		webView.setValue(false, forKey: "drawsBackground")

		searchField = NSSearchField()
		searchField.placeholderString = "Find in preview"
		searchField.target = self
		searchField.action = #selector(findNext)
		searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
		let toolbar = NSStackView(views: [
			button("Contents", action: #selector(toggleContents)), searchField,
			button("Next", action: #selector(findNext)),
			button("Copy", action: #selector(copySource)),
			button("A−", action: #selector(smaller)), button("A+", action: #selector(larger)),
			button("Wrap", action: #selector(toggleWrap)),
		])
		toolbar.spacing = 6
		toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
		let appearance = NSPopUpButton()
		appearance.addItems(withTitles: ["System", "Light", "Dark"])
		appearance.selectItem(at: max(0, min(2, preferences.integer(forKey: "previewAppearance"))))
		appearance.target = self
		appearance.action = #selector(changeAppearance(_:))
		toolbar.addArrangedSubview(appearance)
		changeAppearance(appearance)
		let stack = NSStackView(views: [toolbar, webView])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 0
		stack.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			stack.topAnchor.constraint(equalTo: view.topAnchor),
			stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			toolbar.widthAnchor.constraint(equalTo: stack.widthAnchor),
			webView.widthAnchor.constraint(equalTo: stack.widthAnchor),
		])
		webView.loadHTMLString(documentHTML, baseURL: URL(string: "glance-resource://bundle/"))
	}

	/// Capture the actual web scroll before replacing a controller. Rendering happens after the
	/// replacement enters its view, so the new controller restores only after its ready event.
	func transferState(to replacement: WebPreviewVC, completion: @escaping () -> Void) {
		guard isViewLoaded else {
			completion()
			return
		}
		let search = searchField.stringValue
		webView.evaluateJavaScript(
			"({x: window.scrollX, y: window.scrollY, contents: document.body.classList.contains('contents')})"
		) { value, _ in
			if let values = value as? [String: Any] {
				replacement.pendingScrollState = ScrollState(
					x: (values["x"] as? NSNumber)?.doubleValue ?? 0,
					y: (values["y"] as? NSNumber)?.doubleValue ?? 0,
					contents: values["contents"] as? Bool ?? false,
					search: search
				)
			}
			completion()
		}
	}

	private func restoreScroll() {
		guard let state = pendingScrollState else {
			return
		}
		pendingScrollState = nil
		searchField.stringValue = state.search
		// Images and diagrams can change the document height after the ready message. Keep the
		// requested position through the next few layout passes, unless the user scrolls.
		let script = """
		(() => {
		  document.body.classList.toggle('contents', \(state.contents));
		  const x = \(state.x), y = \(state.y);
		  let active = true;
		  const cancel = () => { active = false; };
		  ['wheel', 'touchstart', 'mousedown', 'keydown'].forEach(name =>
		    window.addEventListener(name, cancel, {once:true, passive:true}));
		  const restore = () => { if (active) window.scrollTo(x, y); };
		  requestAnimationFrame(() => requestAnimationFrame(restore));
		  [120, 400, 900].forEach(delay => setTimeout(restore, delay));
		})();
		"""
		webView.evaluateJavaScript(script, completionHandler: nil)
	}

	private func button(_ title: String, action: Selector) -> NSButton {
		NSButton(title: title, target: self, action: action)
	}

	var documentHTML: String {
		let shared = Bundle.main.url(forResource: "shared-main", withExtension: "css")
		let links = (shared.map { [Stylesheet(url: $0)] } ?? []) + stylesheets
		let fontSize = max(10, min(
			26,
			preferences.integer(forKey: "previewFontSize") == 0
				? 14 : preferences.integer(forKey: "previewFontSize")
		))
		return """
		<!doctype html><html><head><meta charset="utf-8">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src glance-resource: 'unsafe-inline'; style-src glance-resource: 'unsafe-inline'; img-src data:; font-src glance-resource: data:; connect-src 'none'; base-uri 'none'; form-action 'none'">
		\(links.map { $0.getHTML() }.joined(separator: "\n"))
		<style>
		:root { color-scheme: light dark; } body { font-size: \(fontSize)px; }
		#glance-toc { display:none; position:fixed; inset:0 auto 0 0; width:220px; overflow:auto;
		padding:16px; box-sizing:border-box; background:var(--color-background-body); border-right:1px solid var(--color-border); }
		#glance-toc a { display:block; padding:4px 0; overflow-wrap:anywhere; }
		body.contents #glance-toc { display:block; } body.contents main { margin-left:240px; }
		body.wrap pre { white-space:pre-wrap; overflow-wrap:anywhere; }
		.mermaid { text-align:center; } .mermaid svg { max-width:100%; height:auto; }
		pre { counter-reset:line; } .line { display:block; } .line::before { counter-increment:line;
		content:counter(line); display:inline-block; min-width:3em; padding-right:1em; opacity:.45; user-select:none; }
		</style></head><body class="\(preferences.bool(forKey: "previewWrap") ? "wrap" : "")">
		<nav id="glance-toc" aria-label="Table of contents"></nav><main>\(html)</main>
		\(scripts.map { $0.getHTML() }.joined(separator: "\n"))
		<script>
		const toc = document.getElementById('glance-toc');
		document.querySelectorAll('main h1,main h2,main h3').forEach((heading,index) => {
		  if (!heading.id) heading.id = 'heading-' + index;
		  const link = document.createElement('a'); link.href = '#' + heading.id;
		  link.textContent = heading.textContent; link.style.paddingLeft = ((Number(heading.tagName[1])-1)*10)+'px';
		  toc.append(link);
		});
		if (window.glanceReady === undefined) window.glanceReady = true;
			const reportReady = () => window.webkit.messageHandlers.glanceReady.postMessage({
			headings: document.querySelectorAll('main h1,main h2,main h3').length,
			diagrams: document.querySelectorAll('.mermaid svg').length,
			math: document.querySelectorAll('.katex').length,
			text: document.querySelector('main').textContent.length
			});
			if (window.glanceReady) reportReady();
			else document.addEventListener('glance-ready', reportReady, {once:true});
		</script></body></html>
		"""
	}

	@objc
	private func findNext() {
		if #available(macOS 11.0, *) {
			let configuration = WKFindConfiguration()
			configuration.caseSensitive = false
			configuration.wraps = true
			webView.find(searchField.stringValue, configuration: configuration) { _ in }
		}
	}

	@objc
	private func copySource() {
		if let source = source {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(source, forType: .string)
		} else {
			webView.evaluateJavaScript("document.querySelector('main').innerText") { value, _ in
				guard let text = value as? String else {
					return
				}
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(text, forType: .string)
			}
		}
	}

	@objc
	private func toggleContents() {
		webView.evaluateJavaScript(
			"document.body.classList.toggle('contents')",
			completionHandler: nil
		)
	}

	@objc
	private func toggleWrap() {
		let wrap = !preferences.bool(forKey: "previewWrap")
		preferences.set(wrap, forKey: "previewWrap")
		webView.evaluateJavaScript(
			"document.body.classList.toggle('wrap', \(wrap))",
			completionHandler: nil
		)
	}

	@objc
	private func larger() {
		resizeFont(by: 1)
	}

	@objc
	private func smaller() {
		resizeFont(by: -1)
	}

	private func resizeFont(by change: Int) {
		let stored = preferences.integer(forKey: "previewFontSize")
		let current = max(10, min(26, stored == 0 ? 14 : stored))
		let size = max(10, min(26, current + change))
		preferences.set(size, forKey: "previewFontSize")
		webView.evaluateJavaScript(
			"document.body.style.fontSize = '\(size)px'",
			completionHandler: nil
		)
	}

	@objc
	private func changeAppearance(_ sender: NSPopUpButton) {
		let index = max(0, min(2, sender.indexOfSelectedItem))
		preferences.set(index, forKey: "previewAppearance")
		let names: [NSAppearance.Name?] = [nil, .aqua, .darkAqua]
		webView.appearance = names[index].flatMap { NSAppearance(named: $0) }
	}

	func webView(
		_: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		// Anchor navigation stays inside the preview. Other links require the user's normal app.
		if navigationAction.navigationType == .linkActivated {
			if navigationAction.request.url?.fragment != nil,
			   navigationAction.request.url?.scheme == "glance-resource" {
				decisionHandler(.allow)
				return
			}
			if let url = navigationAction.request.url,
			   ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
				NSWorkspace.shared.open(url)
			}
			decisionHandler(.cancel)
			return
		}
		decisionHandler(.allow)
	}
}
