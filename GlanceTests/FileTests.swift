import XCTest

final class FileTests: XCTestCase {
	private var temporaryDirectory: URL!

	override func setUpWithError() throws {
		try super.setUpWithError()
		temporaryDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlanceFileTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(
			at: temporaryDirectory,
			withIntermediateDirectories: true
		)
	}

	override func tearDownWithError() throws {
		if let temporaryDirectory {
			try? FileManager.default.removeItem(at: temporaryDirectory)
		}
		try super.tearDownWithError()
	}

	func testReadsUTF8FileAndMetadata() throws {
		let fileURL = try writeFile(named: "source.swift", contents: "let value = 1\n")

		let file = try File(url: fileURL)

		XCTAssertFalse(file.isDirectory)
		XCTAssertEqual(try file.read(), "let value = 1\n")
		XCTAssertGreaterThan(file.size, 0)
	}

	func testDetectsDirectories() throws {
		let directoryURL = temporaryDirectory.appendingPathComponent("folder", isDirectory: true)
		try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

		let file = try File(url: directoryURL)

		XCTAssertTrue(file.isDirectory)
	}

	func testArchiveDetectionCoversEveryArchivePreviewAlias() throws {
		let archiveNames = [
			"archive.7z",
			"archive.ear",
			"archive.jar",
			"archive.tar",
			"archive.tar.gz",
			"archive.tgz",
			"archive.war",
			"archive.zip",
			"ARCHIVE.ZIP",
		]

		for archiveName in archiveNames {
			let fileURL = try writeFile(named: archiveName, contents: "fixture")
			XCTAssertTrue(try File(url: fileURL).isArchive, archiveName)
		}
	}

	func testPlainGzipIsNotTreatedAsArchivePreview() throws {
		let fileURL = try writeFile(named: "compressed.gz", contents: "fixture")

		XCTAssertFalse(try File(url: fileURL).isArchive)
	}

	func testMissingFileThrows() {
		let missingURL = temporaryDirectory.appendingPathComponent("missing.txt")

		XCTAssertThrowsError(try File(url: missingURL))
	}

	private func writeFile(named name: String, contents: String) throws -> URL {
		let fileURL = temporaryDirectory.appendingPathComponent(name)
		try contents.write(to: fileURL, atomically: true, encoding: .utf8)
		return fileURL
	}
}
