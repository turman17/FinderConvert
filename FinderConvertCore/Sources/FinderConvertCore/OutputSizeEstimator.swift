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
        var videoPreset: String
        var audioBitrate: Int
        var sampleRate: Int

        init(format: OutputFormat, preset: PresetSettings?) {
            let prefs = PreferencesManager.shared
            var q = prefs.quality(for: format)
            if let preset {
                switch format {
                case .jpeg: q = preset.jpegQuality ?? q
                case .heic: q = preset.heicQuality ?? q
                case .webp: q = preset.webpQuality ?? q
                case .avif: q = preset.avifQuality ?? q
                default: break
                }
            }
            quality = q
            resizePercent = preset?.resizePercent ?? prefs.resizePercent(for: format)
            videoPreset = preset?.videoPreset ?? prefs.videoPreset(for: format)
            audioBitrate = preset?.audioBitrate ?? prefs.audioBitrate(for: format)
            sampleRate = prefs.audioSampleRate(for: format)
        }
    }

    public func estimate(
        url: URL,
        input: DetectedFileType,
        output: OutputFormat,
        preset: PresetSettings? = nil
    ) async -> Int64? {
        let settings = Settings(format: output, preset: preset)
        switch input.category {
        case .image:
            return estimateImage(url: url, output: output, settings: settings)
        case .video:
            return await estimateFromVideo(url: url, output: output, settings: settings)
        case .audio:
            return await estimateAudio(url: url, output: output, settings: settings)
        default:
            // Documents/spreadsheets vary too wildly to guess honestly
            return nil
        }
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
            let scale = Double(max(1, min(settings.resizePercent, 100))) / 100.0
            pixels = Double(width) * Double(height) * scale * scale
        }

        let q = settings.quality
        let bytesPerPixel: Double
        switch output {
        case .jpeg: bytesPerPixel = 0.8 * q * q + 0.1
        case .webp: bytesPerPixel = 0.55 * q * q + 0.06
        case .heic, .avif: bytesPerPixel = 0.45 * q * q + 0.05
        case .png: bytesPerPixel = 1.8
        case .tiff: bytesPerPixel = 4.0
        case .bmp: bytesPerPixel = 3.0
        case .gif: bytesPerPixel = 0.9
        case .ico: bytesPerPixel = 1.2
        default: return nil
        }
        return max(2_048, Int64(pixels * bytesPerPixel))
    }

    // MARK: - Video

    private func estimateFromVideo(url: URL, output: OutputFormat, settings: Settings) async -> Int64? {
        let sourceSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0

        switch output {
        case .mp4, .mov, .hevc:
            guard sourceSize > 0 else { return nil }
            let ratio: Double
            if output == .hevc {
                switch settings.videoPreset {
                case "low", "medium": ratio = 0.35 // 1080p cap
                case "high": ratio = 0.5 // 4K cap
                default: ratio = 0.55
                }
            } else {
                switch settings.videoPreset {
                case "low": ratio = 0.12
                case "medium": ratio = 0.35
                default: ratio = 0.9
                }
            }
            return max(50_000, Int64(Double(sourceSize) * ratio))
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
        let pcmBytesPerSecond = Double(settings.sampleRate) * 2 * 2 // stereo, 16-bit
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
