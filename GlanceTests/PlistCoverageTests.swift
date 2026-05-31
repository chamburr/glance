import XCTest

final class PlistCoverageTests: XCTestCase {
	func testQuickLookInfoPlistContainsRepresentativeSupportedContentTypes() throws {
		let supportedTypes = try quickLookSupportedContentTypes()
		let requiredTypes = [
			"org.7-zip.7-zip-archive",
			"com.sun.java-archive",
			"com.sun.web-application-archive",
			"org.gnu.gnu-zip-archive",
			"org.gnu.gnu-zip-tar-archive",
			"public.tar-archive",
			"public.zip-archive",
			"org.jupyter.ipynb",
			"public.jupyter-notebook",
			"public.markdown",
			"net.daringfireball.markdown",
			"public.tab-separated-values-text",
			"public.source-code",
			"public.swift-source",
			"public.toml",
			"public.plain-text",
		]

		for requiredType in requiredTypes {
			XCTAssertTrue(supportedTypes.contains(requiredType), requiredType)
		}
	}

	func testQuickLookSupportedContentTypesAreUnique() throws {
		let supportedTypes = try quickLookSupportedContentTypes()

		XCTAssertEqual(Set(supportedTypes).count, supportedTypes.count)
	}

	private func quickLookSupportedContentTypes() throws -> [String] {
		let plistURL = repositoryRoot()
			.appendingPathComponent("QLPlugin", isDirectory: true)
			.appendingPathComponent("Info.plist")
		let data = try Data(contentsOf: plistURL)
		guard
			let plist = try PropertyListSerialization.propertyList(
				from: data,
				options: [],
				format: nil
			) as? [String: Any],
			let extensionDictionary = plist["NSExtension"] as? [String: Any],
			let attributes = extensionDictionary["NSExtensionAttributes"] as? [String: Any],
			let supportedTypes = attributes["QLSupportedContentTypes"] as? [String]
		else {
			return XCTFailAndReturn("Could not read QLSupportedContentTypes from \(plistURL.path)")
		}

		return supportedTypes
	}

	private func repositoryRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}
}

private func XCTFailAndReturn<T>(_ message: String, file: StaticString = #filePath, line: UInt = #line)
	-> T
{
	XCTFail(message, file: file, line: line)
	fatalError(message)
}
