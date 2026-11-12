import AVFoundation
import CoreMedia
import Foundation
import ImageIO

// Compression re-encodes a file into its own format with smaller settings.
// The engines already handle same-format conversions; this decides which
// formats are worth it, which settings apply, and what the result will cost.
public enum Compression {
    // Target id used in place of an OutputFormat raw value ("keep format")
    public static let targetId = "compress"
    public static let outputSuffix = " compressed"

    // Every image and audio format FinderConvert can write back in its own
    // format, plus MP4/MOV. Lossless formats shrink through palette PNGs,
    // LZW TIFFs, resizing, or a lower sample rate and channel count
    public static func isCompressible(_ type: DetectedFileType) -> Bool {
        sameFormat(type) != nil
    }

    private static func sameFormat(_ type: DetectedFileType) -> OutputFormat? {
        switch type {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        case .gif: .gif
        case .bmp: .bmp
        case .webp: .webp
        case .avif: .avif
        case .mp3: .mp3
        case .m4a: .m4a
        case .wav: .wav
        case .aiff: .aiff
        case .flac: .flac
        case .mp4: .mp4
        case .mov: .mov
        default: nil
        }
    }

    // The same-format output for a file. MOV keeps its codec: iPhone HEVC
    // footage stays HEVC, as H.264 at equal quality would be larger
    // Animated GIFs are left alone: the image engine writes one frame
    public static func target(for url: URL, type: DetectedFileType) async -> OutputFormat? {
        switch type {
        case .mov: return await isHEVC(url) ? .hevc : .mov
        case .gif: return isAnimated(url) ? nil : .gif
        default: return sameFormat(type)
        }
    }

    // Whether a preset carries settings for this category of file
    public static func preset(_ preset: PresetSettings, appliesTo category: FileCategory) -> Bool {
        switch category {
        case .image:
            return preset.jpegQuality != nil || preset.heicQuality != nil || preset.webpQuality != nil
                || preset.avifQuality != nil || preset.pngQuality != nil || preset.resizePercent != nil
                || preset.maxLongestEdge != nil
        case .video: return preset.videoPreset != nil
        case .audio: return preset.audioBitrate != nil
        default: return false
        }
    }

    // Picker label for the "keep format" entry, naming the format when every
    // compressible file shares one. nil when nothing in the list compresses
    public static func pickerLabel(for urls: [URL]) -> String? {
        let detector = FileTypeDetector()
        let types = Set(urls.compactMap { try? detector.detect(url: $0).detectedType }.filter(isCompressible))
        guard !types.isEmpty else { return nil }
        if types.count == 1, let only = types.first, let format = sameFormat(only) {
            return "\(format.displayName) (Compress)"
        }
        return "Same Format (Compress)"
    }

    // Predicted compressed size; nil for files that won't be compressed.
    // `allowProbe: false` skips the video probe encode for callers that
    // must answer quickly (the Finder menu)
    public static func estimate(url: URL, type: DetectedFileType, preset: PresetSettings?, allowProbe: Bool = true) async -> Int64? {
        guard let output = await target(for: url, type: type) else { return nil }
        let estimate: Int64?
        if type.category == .image {
            estimate = await imageEstimate(url: url, output: output, preset: preset)
        } else if output.supportsAudioChannels {
            estimate = await losslessAudioEstimate(url: url, output: output, preset: preset)
        } else {
            estimate = await OutputSizeEstimator().estimate(url: url, input: type, output: output, preset: preset, allowProbe: allowProbe)
        }
        // Outputs that wouldn't be smaller are discarded, keeping the original
        guard let estimate, let source = fileSize(url) else { return estimate }
        return min(estimate, source)
    }

    // Recompressing depends on how the source was encoded, which a
    // bytes-per-pixel formula can't know. Encode a centre crop at the output
    // resolution with the real settings and scale the bytes by area
    static func imageEstimate(url: URL, output: OutputFormat, preset: PresetSettings?) async -> Int64? {
        let settings = OutputSizeEstimator.Settings(format: output, preset: preset)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }

        // Same scaling order as the image engine: percentage, then edge cap
        var scale = settings.resizePercent > 0 && settings.resizePercent < 100 ? Double(settings.resizePercent) / 100 : 1
        let longest = Double(max(width, height)) * scale
        if settings.maxLongestEdge > 0, longest > Double(settings.maxLongestEdge) {
            scale *= Double(settings.maxLongestEdge) / longest
        }
        let image: CGImage?
        if scale < 1 {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int((Double(max(width, height)) * scale).rounded()),
            ] as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { return nil }

        guard let sample = mosaic(of: image),
              let data = try? await NativeImageConversionEngine().encode(sample, format: output, quality: settings.quality, metadata: [:])
        else { return nil }
        let area = Double(image.width * image.height) / Double(sample.width * sample.height)
        let bytes = Int64(Double(data.count) * area)
        return settings.maxOutputBytes > 0 ? min(bytes, settings.maxOutputBytes) : bytes
    }

    // 4x4 tiles of 256 px spread over the image, so busy centres and flat
    // borders both count. Tile edges sit on JPEG's 8 px block grid
    private static func mosaic(of image: CGImage) -> CGImage? {
        let tile = 256, grid = 4
        guard image.width > tile * grid || image.height > tile * grid else { return image }
        let columns = min(grid, max(1, image.width / tile)), rows = min(grid, max(1, image.height / tile))
        let tileWidth = min(tile, image.width), tileHeight = min(tile, image.height)
        guard let context = CGContext(
            data: nil, width: tileWidth * columns, height: tileHeight * rows, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        for row in 0..<rows {
            for column in 0..<columns {
                let x = columns == 1 ? 0 : (image.width - tileWidth) * column / (columns - 1)
                let y = rows == 1 ? 0 : (image.height - tileHeight) * row / (rows - 1)
                guard let piece = image.cropping(to: CGRect(x: x, y: y, width: tileWidth, height: tileHeight)) else { return nil }
                context.draw(piece, in: CGRect(x: column * tileWidth, y: row * tileHeight, width: tileWidth, height: tileHeight))
            }
        }
        return context.makeImage()
    }

    // WAV/AIFF/FLAC scale with sample rate, channels and bit depth (output is
    // always 16-bit), so the source's own size is the best predictor
    private static func losslessAudioEstimate(url: URL, output: OutputFormat, preset: PresetSettings?) async -> Int64? {
        let settings = OutputSizeEstimator.Settings(format: output, preset: preset)
        guard let source = fileSize(url),
              let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first,
              let description = try? await track.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else { return nil }

        let bits: Double
        if asbd.mFormatID == kAudioFormatLinearPCM {
            bits = Double(asbd.mBitsPerChannel)
        } else {
            // FLAC and Apple Lossless record the source depth in the flags
            switch asbd.mFormatFlags {
            case 2: bits = 20
            case 3: bits = 24
            case 4: bits = 32
            default: bits = 16
            }
        }
        guard bits > 0 else { return nil }
        let ratio = (Double(settings.sampleRate) / asbd.mSampleRate)
            * (Double(settings.channels) / Double(asbd.mChannelsPerFrame))
            * (16 / bits)
        return Int64(Double(source) * ratio)
    }

    // Size on disk, read fresh: URL.resourceValues caches per URL instance
    static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int).map(Int64.init)
    }

    private static func isAnimated(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    private static func isHEVC(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let descriptions = try? await track.load(.formatDescriptions) else { return false }
        return descriptions.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC }
    }
}

// Finder menu size estimates, answered by the main app over MenuQuery
public struct CompressionEstimate: Codable, Sendable {
    public let sourceBytes: Int64
    // Keyed by preset name; "" is the current settings
    public let estimates: [String: Int64]

    public init(sourceBytes: Int64, estimates: [String: Int64]) {
        self.sourceBytes = sourceBytes
        self.estimates = estimates
    }

    // Plain files only, few enough to answer within the menu's time budget
    public static let maxFiles = 40

    // Every compressible file under every preset, or nil when any estimate
    // is missing (a partial total would understate the result)
    public static func compute(urls: [URL], presetNames: [String]) async -> CompressionEstimate? {
        guard urls.count <= maxFiles else { return nil }
        let detector = FileTypeDetector()
        let files = urls.compactMap { url -> (URL, DetectedFileType)? in
            guard let type = try? detector.detect(url: url).detectedType, Compression.isCompressible(type) else { return nil }
            return (url, type)
        }
        guard !files.isEmpty else { return nil }

        let sourceBytes = files.compactMap { Compression.fileSize($0.0) }.reduce(0, +)
        var estimates: [String: Int64] = [:]
        for name in [""] + presetNames {
            let preset = name.isEmpty ? nil : PreferencesManager.shared.presetSettings(named: name)
            var total: Int64 = 0
            for (url, type) in files {
                // A preset only changes the files it has settings for
                let applicable = preset.flatMap { Compression.preset($0, appliesTo: type.category) ? $0 : nil }
                guard let estimate = await Compression.estimate(url: url, type: type, preset: applicable, allowProbe: false) else { return nil }
                total += estimate
            }
            estimates[name] = total
        }
        return CompressionEstimate(sourceBytes: sourceBytes, estimates: estimates)
    }
}
