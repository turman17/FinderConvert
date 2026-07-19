import Foundation
import AppKit
import PDFKit
import OSLog
import UniformTypeIdentifiers

public actor PdfConversionEngine: ConversionEngine {
    public let identifier = "com.finderconvert.engine.document.pdf"
    private let logger = Logger(subsystem: "FinderConvert", category: "pdf-engine")
    private let naming = OutputNamingStrategy()

    public init() {}

    public nonisolated func supports(input: DetectedFileType, output: OutputFormat) -> Bool {
        // PDF to Image
        if input == .pdf {
            switch output {
            case .jpeg, .png, .heic, .tiff:
                return true
            default:
                return false
            }
        }
        
        // Image to PDF
        if output == .pdf {
            switch input {
            case .jpeg, .png, .heic, .tiff:
                return true
            default:
                return false
            }
        }
        
        return false
    }

    public func convert(
        job: ConversionJob,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ConversionResult {
        var isStale = false
        let sourceURL = try URL(
            resolvingBookmarkData: job.sourceBookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return try SecurityScopedAccess(url: sourceURL).perform {
            let inputType = try FileTypeDetector().detect(url: sourceURL).detectedType
            guard supports(input: inputType, output: job.requestedOutput) else {
                throw ConversionError.unsupportedOutput(job.requestedOutput)
            }

            if inputType == .pdf {
                // PDF -> Images (all pages)
                guard let pdfDocument = PDFDocument(url: sourceURL), pdfDocument.pageCount > 0 else {
                    throw ConversionError.failedToDecodeImage
                }

                let ext = job.requestedOutput.preferredExtension
                let baseName = sourceURL.deletingPathExtension().lastPathComponent
                let parentDir = sourceURL.deletingLastPathComponent()

                // Single page → single file beside source
                if pdfDocument.pageCount == 1 {
                    let destinationURL = try naming.destinationURL(
                        for: sourceURL, outputFormat: job.requestedOutput, policy: job.destinationPolicy)
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                    defer { try? FileManager.default.removeItem(at: tempURL) }

                    let cgImage = try renderPage(pdfDocument.page(at: 0)!)
                    try writeImage(cgImage, to: tempURL, format: job.requestedOutput)
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    progress(1.0)
                    return ConversionResult(sourceURL: sourceURL, outputURL: destinationURL, outputFormat: job.requestedOutput)
                }

                // Multiple pages → folder with one image per page
                var folderURL = parentDir.appendingPathComponent(baseName)
                var counter = 2
                while FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
                    folderURL = parentDir.appendingPathComponent("\(baseName) \(counter)")
                    counter += 1
                }
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

                let digits = String(pdfDocument.pageCount).count
                var firstOutput: URL?

                for i in 0..<pdfDocument.pageCount {
                    guard let page = pdfDocument.page(at: i) else { continue }
                    let pageNum = String(format: "%0\(digits)d", i + 1)
                    let pageURL = folderURL.appendingPathComponent("\(baseName) - Page \(pageNum).\(ext)")

                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)

                    let cgImage = try renderPage(page)
                    try writeImage(cgImage, to: tempURL, format: job.requestedOutput)
                    try FileManager.default.moveItem(at: tempURL, to: pageURL)

                    if firstOutput == nil { firstOutput = pageURL }
                    progress(Double(i + 1) / Double(pdfDocument.pageCount))
                }

                guard let output = firstOutput else { throw ConversionError.failedToDecodeImage }
                return ConversionResult(sourceURL: sourceURL, outputURL: output, outputFormat: job.requestedOutput)

            } else {
                // Image -> PDF
                let destinationURL = try naming.destinationURL(
                    for: sourceURL, outputFormat: job.requestedOutput, policy: job.destinationPolicy)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
                defer { try? FileManager.default.removeItem(at: tempURL) }

                guard let image = NSImage(contentsOf: sourceURL) else {
                    throw ConversionError.failedToDecodeImage
                }

                let pdfDocument = PDFDocument()
                guard let pdfPage = PDFPage(image: image) else {
                    throw ConversionError.failedToEncodeImage(.pdf)
                }

                pdfDocument.insert(pdfPage, at: 0)
                guard pdfDocument.write(to: tempURL) else {
                    throw ConversionError.failedToEncodeImage(.pdf)
                }

                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                progress(1.0)
                return ConversionResult(sourceURL: sourceURL, outputURL: destinationURL, outputFormat: job.requestedOutput)
            }
        }
    }

    private func renderPage(_ page: PDFPage) throws -> CGImage {
        let pageRect = page.bounds(for: .mediaBox)
        let nsImage = NSImage(size: pageRect.size)
        nsImage.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(pageRect)
            page.draw(with: .mediaBox, to: context)
        }
        nsImage.unlockFocus()

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ConversionError.failedToEncodeImage(.png)
        }
        return cgImage
    }
    
    private func writeImage(_ cgImage: CGImage, to url: URL, format: OutputFormat) throws {
        let utType: UTType
        switch format {
        case .png: utType = .png
        case .jpeg: utType = .jpeg
        case .heic: utType = UTType("public.heic") ?? .image
        case .tiff: utType = .tiff
        default: throw ConversionError.unsupportedOutput(format)
        }
        
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, utType.identifier as CFString, 1, nil) else {
            throw ConversionError.failedToEncodeImage(format)
        }
        
        var options: [CFString: Any] = [:]
        if format == .jpeg || format == .heic {
            options[kCGImageDestinationLossyCompressionQuality] = PreferencesManager.shared.quality(for: format)
        }
        
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.failedToEncodeImage(format)
        }
    }

    public func cancel(jobID: UUID) async {
        // cancellation not currently supported
    }
}
