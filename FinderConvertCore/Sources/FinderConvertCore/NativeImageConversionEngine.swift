import AppKit
import CoreGraphics
import CWebP
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

public actor NativeImageConversionEngine: ConversionEngine {
    public let identifier = "com.finderconvert.engine.image.native"

    private let logger = Logger(subsystem: "FinderConvert", category: "image-engine")
    private let naming = OutputNamingStrategy()

    public init() {}

    private static let supportedInputs: Set<DetectedFileType> = [.jpeg, .png, .heic, .tiff, .gif, .webp, .bmp, .avif]
    private static let supportedOutputs: Set<OutputFormat> = [.jpeg, .png, .heic, .tiff, .gif, .bmp, .ico, .avif, .webp]

    public nonisolated func supports(input: DetectedFileType, output: OutputFormat) -> Bool {
        Self.supportedInputs.contains(input) && Self.supportedOutputs.contains(output)
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

        if isStale {
            logger.notice("Source bookmark was stale and still resolved.")
        }

        return try SecurityScopedAccess(url: sourceURL).perform {
            progress(0.05)
            let inputType = try FileTypeDetector().detect(url: sourceURL).detectedType
            guard supports(input: inputType, output: job.requestedOutput) else {
                logger.error("FinderConvert Engine: Unsupported conversion from \(inputType.rawValue, privacy: .public) to \(job.requestedOutput.rawValue, privacy: .public)")
                throw ConversionError.unsupportedOutput(job.requestedOutput)
            }

            logger.info("FinderConvert Engine: Resolving source URL: \(sourceURL.path(percentEncoded: false), privacy: .public)")
            let sourceData: Data
            do {
                sourceData = try Data(contentsOf: sourceURL)
                logger.info("FinderConvert Engine: Successfully read data. Size: \(sourceData.count, privacy: .public) bytes.")
            } catch {
                logger.error("FinderConvert Engine: Failed to read data from \(sourceURL.path(percentEncoded: false), privacy: .public). Error: \(error.localizedDescription, privacy: .public)")
                throw error
            }

            guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
                logger.error("FinderConvert Engine: CGImageSourceCreateWithData returned nil.")
                throw ConversionError.failedToDecodeImage
            }
            logger.info("FinderConvert Engine: CGImageSourceCreateWithData succeeded.")

            guard var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                logger.error("FinderConvert Engine: CGImageSourceCreateImageAtIndex returned nil for index 0.")
                throw ConversionError.failedToDecodeImage
            }

            // Apply per-format resize if configured (except ICO, which is
            // always rendered at the fixed 256x256 icon size)
            let resizePercent = PreferencesManager.shared.resizePercent(for: job.requestedOutput)
            if resizePercent > 0 && resizePercent < 100 && job.requestedOutput != .ico {
                let scale = Double(resizePercent) / 100.0
                let newW = max(1, Int(Double(image.width) * scale))
                let newH = max(1, Int(Double(image.height) * scale))
                if let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                   let ctx = CGContext(data: nil, width: newW, height: newH, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.interpolationQuality = .high
                    ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
                    if let resized = ctx.makeImage() {
                        image = resized
                        logger.info("Resized image to \(newW)x\(newH) (\(resizePercent)%)")
                    }
                }
            }

            progress(0.35)

            let destinationURL = try naming.destinationURL(
                for: sourceURL,
                outputFormat: job.requestedOutput,
                policy: job.destinationPolicy
            )

            let tempURL = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString, directoryHint: .notDirectory)
                .appendingPathExtension(job.requestedOutput.preferredExtension)

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            switch job.requestedOutput {
            case .png:
                try writeImage(image, source: source, outputFormat: .png, utType: .png, destinationURL: tempURL)
            case .jpeg:
                let flattened = try flattenIfNeeded(image)
                let quality = PreferencesManager.shared.quality(for: .jpeg)
                try writeImage(flattened, source: source, outputFormat: .jpeg, utType: .jpeg, destinationURL: tempURL, properties: [kCGImageDestinationLossyCompressionQuality: quality])
            case .heic:
                let utType = UTType("public.heic") ?? .image
                let quality = PreferencesManager.shared.quality(for: .heic)
                try writeImage(image, source: source, outputFormat: .heic, utType: utType, destinationURL: tempURL, properties: [kCGImageDestinationLossyCompressionQuality: quality])
            case .tiff:
                try writeImage(image, source: source, outputFormat: .tiff, utType: .tiff, destinationURL: tempURL)
            case .gif:
                try writeImage(image, source: source, outputFormat: .gif, utType: .gif, destinationURL: tempURL)
            case .bmp:
                let flattened = try flattenIfNeeded(image)
                try writeImage(flattened, source: source, outputFormat: .bmp, utType: .bmp, destinationURL: tempURL)
            case .ico:
                // ImageIO's ICO encoder only accepts standard icon sizes, so
                // render onto an exact 256x256 square canvas (aspect-fit)
                let squared = try squareCanvas(image, size: 256)
                let flattened = try flattenIfNeeded(squared)
                let icoType = UTType("com.microsoft.ico") ?? .image
                try writeImage(flattened, source: source, outputFormat: .ico, utType: icoType, destinationURL: tempURL)
            case .avif:
                let quality = PreferencesManager.shared.quality(for: .avif)
                let avifType = UTType("public.avif") ?? .image
                try writeImage(image, source: source, outputFormat: .avif, utType: avifType, destinationURL: tempURL, properties: [kCGImageDestinationLossyCompressionQuality: quality])
            case .webp:
                let quality = PreferencesManager.shared.quality(for: .webp)
                try writeWebP(image, quality: Float(quality * 100), to: tempURL)
            default:
                throw ConversionError.unsupportedOutput(job.requestedOutput)
            }

            progress(0.85)
            try validateOutputExists(at: tempURL)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            progress(1.0)
            return ConversionResult(sourceURL: sourceURL, outputURL: destinationURL, outputFormat: job.requestedOutput)
        }
    }

    public func cancel(jobID: UUID) async {}

    private func writeImage(
        _ image: CGImage,
        source: CGImageSource,
        outputFormat: OutputFormat,
        utType: UTType,
        destinationURL: URL,
        properties: [CFString: Any] = [:]
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, utType.identifier as CFString, 1, nil) else {
            throw ConversionError.failedToEncodeImage(outputFormat)
        }

        let shouldStrip = PreferencesManager.shared.stripMetadata(for: outputFormat)
        let metadata: [CFString: Any] = shouldStrip ? [:] : ((CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:])
        let merged = metadata.merging(properties) { _, new in new }
        CGImageDestinationAddImage(destination, image, merged as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.failedToEncodeImage(outputFormat)
        }
    }

    private func flattenIfNeeded(_ image: CGImage) throws -> CGImage {
        if image.alphaInfo == .none || image.alphaInfo == .noneSkipFirst || image.alphaInfo == .noneSkipLast {
            return image
        }

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ConversionError.failedToEncodeImage(.jpeg)
        }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ConversionError.failedToEncodeImage(.jpeg)
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard let flattened = context.makeImage() else {
            throw ConversionError.failedToEncodeImage(.jpeg)
        }

        return flattened
    }

    // Aspect-fit the image centered on a fixed square canvas
    private func squareCanvas(_ image: CGImage, size: Int) throws -> CGImage {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ConversionError.failedToEncodeImage(.ico)
        }
        context.interpolationQuality = .high
        let scale = min(Double(size) / Double(image.width), Double(size) / Double(image.height))
        let w = Double(image.width) * scale
        let h = Double(image.height) * scale
        context.draw(image, in: CGRect(x: (Double(size) - w) / 2, y: (Double(size) - h) / 2, width: w, height: h))
        guard let squared = context.makeImage() else {
            throw ConversionError.failedToEncodeImage(.ico)
        }
        return squared
    }

    private func writeWebP(_ image: CGImage, quality: Float, to url: URL) throws {
        let width = image.width
        let height = image.height
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw ConversionError.failedToEncodeImage(.webp)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { throw ConversionError.failedToEncodeImage(.webp) }

        let rgbData = data.assumingMemoryBound(to: UInt8.self)
        var output: UnsafeMutablePointer<UInt8>?
        let size = WebPEncodeRGBA(rgbData, Int32(width), Int32(height), Int32(width * 4), quality, &output)
        guard size > 0, let outputPtr = output else { throw ConversionError.failedToEncodeImage(.webp) }
        defer { WebPFree(outputPtr) }

        let webpData = Data(bytes: outputPtr, count: Int(size))
        try webpData.write(to: url)
    }

    private func validateOutputExists(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ConversionError.invalidDestination
        }
    }
}
