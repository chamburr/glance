import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let local = directory.appendingPathComponent("fixture.txt")
try "hello".write(to: local, atomically: true, encoding: .utf8)
let text = try File(url: local).read()
precondition(text == "hello")
do {
	_ = try File(url: URL(string: "https://example.invalid" + local.path)!)
	fatalError("Remote URL with existing local path was accepted")
} catch let FileError.fileReadError(_, message) {
	precondition(message == "Only local files can be previewed")
}

do {
	_ = try File(url: directory.appendingPathComponent("missing"))
	fatalError("Missing file accepted")
} catch FileError.fileNotFoundError {}
print("PASS: local file accepted, remote scheme rejected before reading, missing file rejected")
