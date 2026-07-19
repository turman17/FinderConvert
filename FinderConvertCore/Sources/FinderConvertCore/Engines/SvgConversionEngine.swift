import AppKit
import Foundation
import OSLog
import WebKit

public actor SvgConversionEngine: ConversionEngine {
    public let identifier = "com.finderconvert.engine.svg"
    private let logger = Logger(subsystem: "FinderConvert", category: "svg-engine")
    private let naming = OutputNamingStrategy()

    public init() {}

    public nonisolated func supports(input: DetectedFileType, output: OutputFormat) -> Bool {
        guard input == .svg else { return false }
        switch output {
        case .png, .jpeg, .pdf, .tiff, .bmp, .gif, .heic, .avif, .ico:
            return true
        default:
            return false
        }
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

        let access = SecurityScopedAccess(url: sourceURL)
        progress(0.1)

        let destinationURL = try naming.destinationURL(
            for: sourceURL,
            outputFormat: job.requestedOutput,
            policy: job.destinationPolicy
        )

        // Render SVG via NSImage (macOS natively supports SVG rendering)
        let svgData = try Data(contentsOf: sourceURL)
        guard let svgImage = NSImage(data: svgData) else {
            throw ConversionError.failedToDecodeImage
        }

        // Get SVG dimensions, default to 1024 if not available
        var size = svgImage.size
        if size.width <= 0 || size.height <= 0 {
            size = NSSize(width: 1024, height: 1024)
        }

        // Scale up if SVG is small (vector should render at high res)
        let minDim: CGFloat = 1024
        if size.width < minDim && size.height < minDim {
            let scale = minDim / max(size.width, size.height)
            size = NSSize(width: size.width * scale, height: size.height * scale)
        }

        progress(0.3)

        // Render to bitmap
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ConversionError.failedToEncodeImage(job.requestedOutput)
        }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current = context

        // White background for formats that don't support alpha
        let needsBackground = [OutputFormat.jpeg, .bmp, .ico].contains(job.requestedOutput)
        if needsBackground {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()
        }

        svgImage.draw(in: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()

        progress(0.6)

        // If output is PDF, render via NSView
        if job.requestedOutput == .pdf {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
            let svgSize = size
            let svgImg = svgImage
            try await MainActor.run {
                let imageView = NSImageView(frame: NSRect(origin: .zero, size: svgSize))
                imageView.image = svgImg
                let pdfData = imageView.dataWithPDF(inside: imageView.bounds)
                try pdfData.write(to: tempURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            try? FileManager.default.removeItem(at: tempURL)
            _ = access
            progress(1.0)
            return ConversionResult(sourceURL: sourceURL, outputURL: destinationURL, outputFormat: job.requestedOutput)
        }

        // Convert bitmap to CGImage for other formats
        guard var cgImage = bitmapRep.cgImage else {
            throw ConversionError.failedToEncodeImage(job.requestedOutput)
        }

        // ICO needs resize to 256x256 max
        if job.requestedOutput == .ico {
            let maxDim = max(cgImage.width, cgImage.height)
            if maxDim > 256 {
                let scale = 256.0 / Double(maxDim)
                let newW = max(1, Int(Double(cgImage.width) * scale))
                let newH = max(1, Int(Double(cgImage.height) * scale))
                if let cs = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                   let ctx = CGContext(data: nil, width: newW, height: newH, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                    ctx.interpolationQuality = .high
                    ctx.setFillColor(NSColor.white.cgColor)
                    ctx.fill(CGRect(x: 0, y: 0, width: newW, height: newH))
                    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
                    if let resized = ctx.makeImage() { cgImage = resized }
                }
            }
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(job.requestedOutput.preferredExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try writeImage(cgImage, to: tempURL, format: job.requestedOutput)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        _ = access
        progress(1.0)
        return ConversionResult(sourceURL: sourceURL, outputURL: destinationURL, outputFormat: job.requestedOutput)
    }

    public func cancel(jobID: UUID) async {}

    private func writeImage(_ cgImage: CGImage, to url: URL, format: OutputFormat) throws {
        let utType: String
        var properties: [CFString: Any] = [:]

        switch format {
        case .png: utType = "public.png"
        case .jpeg:
            utType = "public.jpeg"
            properties[kCGImageDestinationLossyCompressionQuality] = PreferencesManager.shared.quality(for: .jpeg)
        case .heic:
            utType = "public.heic"
            properties[kCGImageDestinationLossyCompressionQuality] = PreferencesManager.shared.quality(for: .heic)
        case .avif:
            utType = "public.avif"
            properties[kCGImageDestinationLossyCompressionQuality] = PreferencesManager.shared.quality(for: .avif)
        case .tiff: utType = "public.tiff"
        case .gif: utType = "com.compuserve.gif"
        case .bmp: utType = "com.microsoft.bmp"
        case .ico: utType = "com.microsoft.ico"
        default: throw ConversionError.unsupportedOutput(format)
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType as CFString, 1, nil) else {
            throw ConversionError.failedToEncodeImage(format)
        }
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.failedToEncodeImage(format)
        }
    }
}
