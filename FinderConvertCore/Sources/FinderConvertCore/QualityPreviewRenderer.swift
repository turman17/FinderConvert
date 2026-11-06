import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// A bundled sample picture encoded with exactly the settings a format would
// use, so the settings UI can show what a quality level looks like instead
// of a bare percentage
public struct QualityPreview: @unchecked Sendable {
    public let original: CGImage
    public let encoded: CGImage
    // Encoded size of the sample; 0 when it says nothing useful (video)
    public let encodedBytes: Int
    public let bytesPerMegapixel: Int?
}

public enum QualityPreviewRenderer {
    public static func supportsPreview(_ format: OutputFormat) -> Bool {
        format.supportsQuality || format.supportsVideoQuality
    }

    public static func sample() -> CGImage? {
        guard let url = Bundle.module.url(forResource: "quality-sample", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func render(format: OutputFormat, quality: Double, videoPreset: String) async throws -> QualityPreview {
        guard let original = sample() else { throw ConversionError.failedToDecodeImage }

        let data: Data
        switch format {
        case .jpeg:
            data = try encode(original, utType: .jpeg, quality: quality)
        case .heic:
            data = try encode(original, utType: UTType("public.heic") ?? .heic, quality: quality)
        case .avif:
            data = try encode(original, utType: UTType("public.avif") ?? .image, quality: quality)
        case .webp:
            data = try NativeImageConversionEngine.encodeWebP(original, quality: Float(quality * 100))
        case .mp4, .mov, .hevc:
            return try await renderVideoFrame(original, format: format, preset: videoPreset)
        default:
            throw ConversionError.unsupportedOutput(format)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConversionError.failedToDecodeImage
        }
        let megapixels = Double(original.width * original.height) / 1_000_000
        return QualityPreview(
            original: original,
            encoded: decoded,
            encodedBytes: data.count,
            bytesPerMegapixel: Int(Double(data.count) / megapixels)
        )
    }

    private static func encode(_ image: CGImage, utType: UTType, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, utType.identifier as CFString, 1, nil) else {
            throw ConversionError.failedToEncodeImage(.jpeg)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.failedToEncodeImage(.jpeg) }
        return data as Data
    }

    // Push the sample through the same hardware encoder and constant-quality
    // value the video engine uses, as a single frame, and read it back
    private static func renderVideoFrame(_ image: CGImage, format: OutputFormat, preset: String) async throws -> QualityPreview {
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .notDirectory)
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let codec: AVVideoCodecType = format == .hevc ? .hevc : .h264
        let settings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: image.width,
            AVVideoHeightKey: image.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: VideoRateModel.encoderQuality(for: preset),
            ],
        ]
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: image.width,
            kCVPixelBufferHeightKey as String: image.height,
        ])
        writer.add(input)
        guard writer.startWriting() else {
            throw ConversionError.filesystemError(writer.error?.localizedDescription ?? "Could not start the video encoder.")
        }
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else { throw ConversionError.failedToEncodeImage(format) }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else { throw ConversionError.failedToEncodeImage(format) }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard adaptor.append(buffer, withPresentationTime: .zero) else {
            throw ConversionError.failedToEncodeImage(format)
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ConversionError.filesystemError(writer.error?.localizedDescription ?? "Video encoding did not complete.")
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: tempURL))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let (decoded, _) = try await generator.image(at: .zero)
        return QualityPreview(original: image, encoded: decoded, encodedBytes: 0, bytesPerMegapixel: nil)
    }
}
