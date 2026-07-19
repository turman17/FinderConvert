import FinderConvertCore
import XCTest

final class TypeDetectionTests: XCTestCase {
    func testJPEGFallbackDetectionUsesFileExtension() {
        let detector = FileTypeDetector()
        XCTAssertEqual(detector.fallbackDetectedType(for: "jpg"), .jpeg)
        XCTAssertEqual(detector.fallbackDetectedType(for: "jpeg"), .jpeg)
    }

    func testPNGFallbackDetectionUsesFileExtension() {
        let detector = FileTypeDetector()
        XCTAssertEqual(detector.fallbackDetectedType(for: "png"), .png)
    }

    func testUnsupportedFallbackDetectionRejectsUnknownExtension() {
        let detector = FileTypeDetector()
        XCTAssertEqual(detector.fallbackDetectedType(for: "xyz"), .unsupported)
    }
}
