import Foundation
import PDFKit
import OSLog

public struct PdfToolsService: Sendable {
    private let logger = Logger(subsystem: "FinderConvert", category: "pdf-tools")

    public init() {}

    /// Merge multiple PDFs into one. Output is placed beside the first file.
    public func merge(urls: [URL]) throws -> URL {
        guard urls.count >= 2 else {
            throw ConversionError.filesystemError("Need at least 2 PDFs to merge.")
        }

        let mergedDoc = PDFDocument()
        var pageIndex = 0

        for url in urls {
            guard let doc = PDFDocument(url: url) else {
                logger.warning("Could not open PDF: \(url.lastPathComponent, privacy: .public)")
                continue
            }
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) {
                    mergedDoc.insert(page, at: pageIndex)
                    pageIndex += 1
                }
            }
        }

        guard mergedDoc.pageCount > 0 else {
            throw ConversionError.filesystemError("No pages found in the selected PDFs.")
        }

        // Name output after first file
        let baseName = urls[0].deletingPathExtension().lastPathComponent
        let parentDir = urls[0].deletingLastPathComponent()
        var outputURL = parentDir.appendingPathComponent("\(baseName) merged.pdf")

        // Avoid collision
        var counter = 2
        while FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) {
            outputURL = parentDir.appendingPathComponent("\(baseName) merged \(counter).pdf")
            counter += 1
        }

        guard mergedDoc.write(to: outputURL) else {
            throw ConversionError.filesystemError("Failed to write merged PDF.")
        }

        logger.info("Merged \(urls.count) PDFs (\(pageIndex) pages) → \(outputURL.lastPathComponent, privacy: .public)")
        return outputURL
    }

    /// Split a PDF into one file per page. Output goes into a folder named after the PDF.
    public func split(url: URL) throws -> [URL] {
        guard let doc = PDFDocument(url: url) else {
            throw ConversionError.filesystemError("Could not open PDF.")
        }

        guard doc.pageCount > 0 else {
            throw ConversionError.filesystemError("PDF has no pages.")
        }

        let baseName = url.deletingPathExtension().lastPathComponent
        let parentDir = url.deletingLastPathComponent()

        // Create output folder
        var folderURL = parentDir.appendingPathComponent("\(baseName) pages")
        var counter = 2
        while FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
            folderURL = parentDir.appendingPathComponent("\(baseName) pages \(counter)")
            counter += 1
        }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var outputURLs: [URL] = []
        let digits = String(doc.pageCount).count

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let pageDoc = PDFDocument()
            pageDoc.insert(page, at: 0)

            let pageNum = String(format: "%0\(digits)d", i + 1)
            let pageURL = folderURL.appendingPathComponent("\(baseName) - Page \(pageNum).pdf")

            guard pageDoc.write(to: pageURL) else {
                logger.warning("Failed to write page \(i + 1)")
                continue
            }
            outputURLs.append(pageURL)
        }

        logger.info("Split \(url.lastPathComponent, privacy: .public) into \(outputURLs.count) pages")
        return outputURLs
    }
}
