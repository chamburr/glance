import Foundation

let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }
func check(_ condition: @autoclosure () throws -> Bool) rethrows {
	let result = try condition(); precondition(result)
}

let json = scratch.appendingPathComponent("sample.json")
try Data("{\"z\":2,\"a\":1}".utf8).write(to: json)
let formatted = try CodePreview().getSource(file: File(url: json))
check(formatted.contains("\n")); check(formatted.range(of: "a")!.lowerBound < formatted
	.range(of: "z")!.lowerBound)
try Data("{bad".utf8).write(to: json)
try check(try CodePreview().getSource(file: File(url: json)) == "{bad")
let plist = scratch.appendingPathComponent("sample.plist")
try PropertyListSerialization.data(fromPropertyList: ["name": "value"], format: .binary, options: 0)
	.write(to: plist)
try check(try CodePreview().getSource(file: File(url: plist)).contains("<string>value</string>"))
let xml = scratch.appendingPathComponent("sample.xml")
let doctype = "<!DOCTYPE root SYSTEM \"file:///missing\"><root/>"
try Data(doctype.utf8).write(to: xml)
try check(try CodePreview().getSource(file: File(url: xml)) == doctype)
print("PASS structured formatting: JSON sort/format/fallback, binary plist, DOCTYPE preserved")
