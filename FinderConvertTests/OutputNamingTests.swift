import FinderConvertCore
import XCTest

final class OutputNamingTests: XCTestCase {
    func testFirstCollisionUsesConvertedSuffix() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appending(path: "sample.png", directoryHint: .notDirectory)
        try Data().write(to: sourceURL)

        let destination = try OutputNamingStrategy().destinationURL(for: sourceURL, outputFormat: .jpeg)
        XCTAssertEqual(destination.lastPathComponent, "sample converted.jpg")
    }

    func testLaterCollisionAppendsIndex() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appending(path: "sample.jpg", directoryHint: .notDirectory)
        let first = tempDirectory.appending(path: "sample converted.png", directoryHint: .notDirectory)
        try Data().write(to: sourceURL)
        try Data().write(to: first)

        let destination = try OutputNamingStrategy().destinationURL(for: sourceURL, outputFormat: .png)
        XCTAssertEqual(destination.lastPathComponent, "sample converted 2.png")
    }
}
