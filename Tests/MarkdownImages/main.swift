import Cocoa
import Foundation
import os.log
import WebKit

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
func check(_ value: Bool, _ message: String) {
	if !value { fatalError(message) }
	print("PASS: " + message)
}

class Log { static let parse = OSLog.default; static let render = OSLog.default }
protocol Preview { init() }
protocol PreviewVC {}
class File {
	let url: URL; init(_ url: URL) { self.url = url }; func read() throws -> String { try String(
		contentsOf: url,
		encoding: .utf8
	) }
}

class HTMLRenderer { static func renderMarkdown(_ source: String) throws -> String { source } }
class Stylesheet { init(url _: URL) {} }
class WebPreviewVC: PreviewVC { init(html _: String, stylesheets _: [Stylesheet]) {} }
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let file = directory.appendingPathComponent("example.md")
let bitmap = NSBitmapImageRep(
	bitmapDataPlanes: nil,
	pixelsWide: 2,
	pixelsHigh: 2,
	bitsPerSample: 8,
	samplesPerPixel: 4,
	hasAlpha: true,
	isPlanar: false,
	colorSpaceName: .deviceRGB,
	bytesPerRow: 0,
	bitsPerPixel: 0
)!
let data = bitmap.representation(using: .png, properties: [:])!
try data.write(to: directory.appendingPathComponent("image.png"))
func embed(_ source: String) -> String { MarkdownPreview.inlineLocalImages(
	"<img src=\"" + source + "\">",
	beside: file
) }
check(embed("image.png").contains("data:image/png;base64,"), "local image embeds")
try Data("not an image".utf8).write(to: directory.appendingPathComponent("fake.png"))
check(!embed("fake.png").contains("base64"), "invalid image rejected")
let outside = directory.deletingLastPathComponent()
	.appendingPathComponent("outside-" + UUID().uuidString + ".png")
try data.write(to: outside)
defer { try? FileManager.default.removeItem(at: outside) }
try FileManager.default.createSymbolicLink(
	at: directory.appendingPathComponent("escape.png"),
	withDestinationURL: outside
)
check(!embed("escape.png").contains("base64"), "symlink escape rejected")
check(!embed("../" + outside.lastPathComponent).contains("base64"), "parent traversal rejected")
check(!embed("https://example.com/image.png").contains("base64"), "remote image untouched")
try Data(repeating: 0, count: 5_000_001).write(to: directory.appendingPathComponent("large.png"))
check(!embed("large.png").contains("base64"), "oversize input rejected")
var padded = data
padded.append(Data(repeating: 0, count: 4_500_000 - data.count))
try padded.write(to: directory.appendingPathComponent("padded.png"))
let repeated = String(repeating: "<img src=\"padded.png\">", count: 5)
let bounded = MarkdownPreview.inlineLocalImages(repeated, beside: file)
check(bounded.components(separatedBy: "base64,").count - 1 == 4, "aggregate budget enforced")
