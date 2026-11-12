import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Predicts the rough output size of a conversion before it runs, so the UI
// can show "84 MB → ~9 MB" while the user compares presets and formats.
// Heuristic by design: real encoders vary with content, so callers should
// present results with a "~" prefix, never as a promise.
public struct OutputSizeEstimator: Sendable {
    public init() {}

    // Effective settings for the estimate: explicit preset values win over
    // the current preferences (mirrors how per-file presets apply at convert
    // time)
    struct Settings {
        var quality: Double
        var resizePercent: Int
        var maxLongestEdge: Int
        var maxOutputBytes: Int64
        var videoPreset: String
        var audioBitrate: Int
        var sampleRate: Int
        var channels: Int

        init(format: OutputFormat, preset: PresetSettings?) {
            let prefs = PreferencesManager.shared
            var q = prefs.quality(for: format)
            if let preset {
                switch format {
                case .jpeg: q = preset.jpegQuality ?? q
                case .heic: q = preset.heicQuality ?? q
                case .webp: q = preset.webpQuality ?? q
                case .avif: q = preset.avifQuality ?? q
                case .png: q = preset.pngQuality ?? q
                default: break
                }
            }
            quality = q
            resizePercent = preset?.resizePercent ?? prefs.resizePercent(for: format)
            maxLongestEdge = preset?.maxLongestEdge ?? prefs.maxLongestEdge(for: format)
            maxOutputBytes = prefs.maxOutputBytes
            videoPreset = preset?.videoPreset ?? prefs.videoPreset(for: format)
            audioBitrate = preset?.audioBitrate ?? prefs.audioBitrate(for: format)
            sampleRate = prefs.audioSampleRate(for: format)
            channels = 2
            if format.supportsAudioChannels {
                sampleRate = preset?.audioSampleRate ?? sampleRate
                channels = preset?.audioChannels ?? prefs.audioChannels(for: format)
            }
        }
    }

    public func estimate(
        url: URL,
        input: DetectedFileType,
        output: OutputFormat,
        preset: PresetSettings? = nil,
        allowProbe: Bool = true
    ) async -> Int64? {
        let settings = Settings(format: output, preset: preset)
        let estimate: Int64?
        switch input.category {
        case .image:
            estimate = estimateImage(url: url, output: output, settings: settings)
        case .video:
            estimate = await estimateFromVideo(url: url, output: output, settings: settings, allowProbe: allowProbe)
        case .audio:
            estimate = await estimateAudio(url: url, output: output, settings: settings)
        default:
            // Documents/spreadsheets vary too wildly to guess honestly
            estimate = nil
        }
        // The engines enforce the size cap, so the prediction never exceeds it
        if settings.maxOutputBytes > 0, let estimate, output.supportsQuality || output.supportsVideoQuality || output.category == .image {
            return min(estimate, settings.maxOutputBytes)
        }
        return estimate
    }

    // MARK: - Image

    private func estimateImage(url: URL, output: OutputFormat, settings: Settings) -> Int64? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }

        let pixels: Double
        if output == .ico {
            pixels = 256 * 256 // fixed icon canvas
        } else {
            var scale = Double(max(1, min(settings.resizePercent, 100))) / 100.0
            let longest = Double(max(width, height)) * scale
            if settings.maxLongestEdge > 0, longest > Double(settings.maxLongestEdge) {
                scale *= Double(settings.maxLongestEdge) / longest
            }
            pixels = Double(width) * Double(height) * scale * scale
        }

        let q = settings.quality
        let bytesPerPixel: Double
        switch output {
        case .jpeg: bytesPerPixel = 0.8 * q * q + 0.1
        case .webp: bytesPerPixel = 0.55 * q * q + 0.06
        case .heic, .avif: bytesPerPixel = 0.45 * q * q + 0.05
        case .png:
            // Palette PNGs: one byte per pixel before deflate
            bytesPerPixel = PngQuantizer.colorCount(forQuality: q) == nil ? 1.8 : 0.5
        case .tiff: bytesPerPixel = 2.0 // LZW
        case .bmp: bytesPerPixel = 3.0
        case .gif: bytesPerPixel = 0.9
        case .ico: bytesPerPixel = 1.2
        default: return nil
        }
        return max(2_048, Int64(pixels * bytesPerPixel))
    }

    // MARK: - Video

    private func estimateFromVideo(url: URL, output: OutputFormat, settings: Settings, allowProbe: Bool) async -> Int64? {
        let sourceSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0

        switch output {
        case .mp4, .mov, .hevc:
            guard sourceSize > 0, seconds > 0 else { return nil }
            // Constant-quality output depends on the footage, so encode a
            // short slice from the middle and scale it up (cached per file)
            if allowProbe, let probed = try? await VideoSizeProbe.projectedBytes(sourceURL: url, format: output, preset: settings.videoPreset) {
                return max(50_000, probed)
            }
            // Fallback formula: pixels per second times a measured
            // bits-per-pixel figure, capped at the source's own data rate
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize),
                  size.width > 0, size.height > 0 else { return nil }
            let frameRate = Double((try? await track.load(.nominalFrameRate)) ?? 30)
            let codec: AVVideoCodecType = output == .hevc ? .hevc : .h264
            let bitRate = VideoRateModel.targetBitRate(preset: settings.videoPreset, width: Int(size.width), height: Int(size.height), frameRate: frameRate, codec: codec)
            let videoBytes = min(Double(sourceSize), Double(bitRate) / 8 * seconds)
            let audioBytes = 160_000.0 / 8 * seconds
            return max(50_000, Int64(videoBytes + audioBytes))
        case .gif:
            guard seconds > 0 else { return nil }
            // Engine caps GIFs at 10 fps / 200 frames / 480px
            let frames = min(200.0, seconds * 10)
            return Int64(frames * 35_000)
        case .mp3, .m4a, .wav, .aiff, .flac:
            guard seconds > 0 else { return nil }
            return estimateAudioBytes(seconds: seconds, output: output, settings: settings)
        default:
            return nil
        }
    }

    // MARK: - Audio

    private func estimateAudio(url: URL, output: OutputFormat, settings: Settings) async -> Int64? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds > 0, seconds.isFinite else { return nil }
        return estimateAudioBytes(seconds: seconds, output: output, settings: settings)
    }

    private func estimateAudioBytes(seconds: Double, output: OutputFormat, settings: Settings) -> Int64? {
        let pcmBytesPerSecond = Double(settings.sampleRate) * 2 * Double(settings.channels) // 16-bit
        let bytes: Double
        switch output {
        case .mp3, .m4a: bytes = Double(settings.audioBitrate) / 8 * seconds
        case .wav, .aiff: bytes = pcmBytesPerSecond * seconds
        case .flac: bytes = pcmBytesPerSecond * seconds * 0.6
        default: return nil
        }
        return max(10_000, Int64(bytes))
    }
}
