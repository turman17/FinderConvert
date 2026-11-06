import AVFoundation
import Foundation
import VideoToolbox

// How the encoder is told to spend bits
public enum VideoRateMode: Sendable, Equatable {
    // VideoToolbox's constant-quality scale, the equivalent of ffmpeg's CRF:
    // bits go where the picture needs them, so size depends on the footage
    case constantQuality(Float)
    // Classic average bitrate: predictable size, quality varies with content
    case averageBitRate(Int)
}

public enum VideoRateModel {
    // Maps the "Export quality" setting onto the constant-quality scale.
    // Measured on a detailed 4K clip: 0.75 ≈ VMAF 92, 0.65 ≈ 88,
    // 0.55 ≈ 80, 0.45 ≈ 65. Resolution is never touched
    public static func encoderQuality(for preset: String) -> Float {
        switch preset {
        case "low": return 0.45
        case "medium": return 0.55
        case "high": return 0.65
        default: return 0.75
        }
    }

    // Bits per pixel per level for H.264 at the same visual quality as the
    // constant-quality values above, measured on the same clip. Busy
    // footage; simple footage needs far less
    public static func bitsPerPixel(for preset: String) -> Double {
        switch preset {
        case "low": return 0.025
        case "medium": return 0.05
        case "high": return 0.09
        default: return 0.14
        }
    }

    public static func codecFactor(_ codec: AVVideoCodecType) -> Double {
        codec == .hevc ? 0.6 : 1.0
    }

    public static func targetBitRate(preset: String, width: Int, height: Int, frameRate: Double, codec: AVVideoCodecType) -> Int {
        let fps = frameRate > 0 ? frameRate : 30
        let bits = Double(width * height) * fps * bitsPerPixel(for: preset) * codecFactor(codec)
        return max(200_000, Int(bits))
    }

    // Bitrate that lands a clip under a byte budget, leaving room for the
    // audio track and container overhead
    public static func bitRate(fitting maxBytes: Int64, duration: Double, audioBitRate: Int) -> Int {
        guard duration > 0 else { return 200_000 }
        let total = Double(maxBytes) * 8 / duration
        return max(200_000, Int((total - Double(audioBitRate)) * 0.92))
    }

    public static func audioBitRate(channels: Int) -> Int {
        channels == 1 ? 96_000 : 160_000
    }

    // Whether this Mac's encoder accepts constant-quality mode for the codec
    // (Apple silicon does; older Intel encoders do not)
    public static func supportsConstantQuality(codec: AVVideoCodecType, width: Int, height: Int) -> Bool {
        let codecType: CMVideoCodecType = codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height), codecType: codecType,
            encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session
        )
        guard status == noErr, let session else { return false }
        defer { VTCompressionSessionInvalidate(session) }
        var supported: CFDictionary?
        guard VTSessionCopySupportedPropertyDictionary(session, supportedPropertyDictionaryOut: &supported) == noErr,
              let dict = supported as? [String: Any] else { return false }
        return dict[kVTCompressionPropertyKey_Quality as String] != nil
    }
}

// Re-encodes a movie (or a slice of it) with AVAssetWriter. Used by the
// video engine for real conversions and by the size estimator for short
// probe encodes, so both see exactly the same encoder settings
public actor VideoTranscoder {
    public struct Options: Sendable {
        public var format: OutputFormat
        public var preset: String
        // nil: constant quality when the encoder supports it, else bitrate
        public var rateMode: VideoRateMode?
        // nil: the whole clip
        public var timeRange: CMTimeRange?
        public var includeAudio: Bool

        public init(format: OutputFormat, preset: String, rateMode: VideoRateMode? = nil, timeRange: CMTimeRange? = nil, includeAudio: Bool = true) {
            self.format = format
            self.preset = preset
            self.rateMode = rateMode
            self.timeRange = timeRange
            self.includeAudio = includeAudio
        }
    }

    public struct Result: Sendable {
        public let bytes: Int64
        public let rateMode: VideoRateMode
        public let hdr: Bool
        public let seconds: Double
        public let audioBitRate: Int
    }

    private var writer: AVAssetWriter?
    private var reader: AVAssetReader?
    private var cancelled = false

    public init() {}

    public func cancel() {
        cancelled = true
        reader?.cancelReading()
        writer?.cancelWriting()
    }

    private func isHDR(_ track: AVAssetTrack) async throws -> Bool {
        guard let description = try await track.load(.formatDescriptions).first,
              let transfer = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        else { return false }
        return transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
            || transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
    }

    // Carry the source colour tags across so players render the output the
    // same way. AVAssetWriter rejects values outside its documented set, so
    // anything unusual is left untagged rather than risking an exception
    private func colorProperties(for track: AVAssetTrack) async throws -> [String: Any]? {
        guard let description = try await track.load(.formatDescriptions).first else { return nil }
        func extension_(_ key: CFString) -> String? {
            CMFormatDescriptionGetExtension(description, extensionKey: key) as? String
        }
        guard let primaries = extension_(kCMFormatDescriptionExtension_ColorPrimaries),
              let transfer = extension_(kCMFormatDescriptionExtension_TransferFunction),
              let matrix = extension_(kCMFormatDescriptionExtension_YCbCrMatrix) else { return nil }

        let knownPrimaries: Set<String> = [AVVideoColorPrimaries_ITU_R_709_2, AVVideoColorPrimaries_EBU_3213, AVVideoColorPrimaries_SMPTE_C, AVVideoColorPrimaries_P3_D65, AVVideoColorPrimaries_ITU_R_2020]
        let knownTransfer: Set<String> = [AVVideoTransferFunction_ITU_R_709_2, AVVideoTransferFunction_SMPTE_240M_1995, AVVideoTransferFunction_SMPTE_ST_2084_PQ, AVVideoTransferFunction_ITU_R_2100_HLG]
        let knownMatrix: Set<String> = [AVVideoYCbCrMatrix_ITU_R_709_2, AVVideoYCbCrMatrix_ITU_R_601_4, AVVideoYCbCrMatrix_SMPTE_240M_1995, AVVideoYCbCrMatrix_ITU_R_2020]
        guard knownPrimaries.contains(primaries), knownTransfer.contains(transfer), knownMatrix.contains(matrix) else { return nil }
        return [
            AVVideoColorPrimariesKey: primaries,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: matrix,
        ]
    }

    private static var sdrColorProperties: [String: Any] {
        [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
    }

    @discardableResult
    public func run(
        sourceURL: URL,
        destination: URL,
        options: Options,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Result {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.filesystemError("This file has no video track.")
        }

        let fileType: AVFileType = options.format == .mp4 ? .mp4 : .mov
        let codec: AVVideoCodecType = options.format == .hevc ? .hevc : .h264
        let hdr = try await isHDR(videoTrack)
        // Only the HEVC encoder takes 10-bit input, so HDR stays HDR there;
        // for H.264 the reader tone-maps down to SDR at full resolution
        let keepHDR = hdr && codec == .hevc

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let timescale = try await videoTrack.load(.naturalTimeScale)
        let fullDuration = try await asset.load(.duration)
        let width = Int(naturalSize.width.rounded())
        let height = Int(naturalSize.height.rounded())

        let rateMode: VideoRateMode
        if let forced = options.rateMode {
            rateMode = forced
        } else if VideoRateModel.supportsConstantQuality(codec: codec, width: width, height: height) {
            rateMode = .constantQuality(VideoRateModel.encoderQuality(for: options.preset))
        } else {
            rateMode = .averageBitRate(VideoRateModel.targetBitRate(preset: options.preset, width: width, height: height, frameRate: Double(frameRate), codec: codec))
        }

        var compression: [String: Any] = [
            // B-frames and a 5s GOP: ~15% smaller at the same quality
            AVVideoAllowFrameReorderingKey: true,
            AVVideoMaxKeyFrameIntervalKey: frameRate > 0 ? max(30, Int((frameRate * 5).rounded())) : 150,
        ]
        switch rateMode {
        case .constantQuality(let quality): compression[AVVideoQualityKey] = quality
        case .averageBitRate(let bitRate): compression[AVVideoAverageBitRateKey] = bitRate
        }
        if frameRate > 0 {
            compression[AVVideoExpectedSourceFrameRateKey] = Int(frameRate.rounded())
        }
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        } else if keepHDR {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        }

        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
        if hdr && !keepHDR {
            videoSettings[AVVideoColorPropertiesKey] = Self.sdrColorProperties
        } else if let color = try await colorProperties(for: videoTrack) {
            videoSettings[AVVideoColorPropertiesKey] = color
        }

        let writer = try AVAssetWriter(outputURL: destination, fileType: fileType)
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw ConversionError.filesystemError("The video encoder does not support these settings on this Mac.")
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        // Match the source clock so frame timestamps survive exactly; the
        // default 600 Hz timescale drifts a full frame on 29.97 fps footage
        videoInput.mediaTimeScale = timescale
        writer.movieTimeScale = timescale
        writer.add(videoInput)

        let reader = try AVAssetReader(asset: asset)
        if let range = options.timeRange {
            reader.timeRange = range
        }
        var readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: keepHDR
                ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ]
        if hdr && !keepHDR {
            // Asking the reader for BT.709 output makes it tone-map HDR frames
            readerSettings[AVVideoColorPropertiesKey] = Self.sdrColorProperties
        }
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)

        // Audio is re-encoded as AAC so the file plays everywhere (screen
        // recordings often carry raw PCM, which is not valid in MP4)
        var audioPair: (input: AVAssetWriterInput, output: AVAssetReaderTrackOutput)?
        var audioBitRate = 0
        if options.includeAudio, let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            var sampleRate = 44_100.0
            var channels = 2
            if let description = try await audioTrack.load(.formatDescriptions).first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                if asbd.mSampleRate > 0 { sampleRate = asbd.mSampleRate }
                if asbd.mChannelsPerFrame > 0 { channels = min(2, Int(asbd.mChannelsPerFrame)) }
            }
            audioBitRate = VideoRateModel.audioBitRate(channels: channels)
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: audioBitRate,
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
            ])
            reader.add(audioOutput)
            audioPair = (audioInput, audioOutput)
        }

        if cancelled { throw ConversionError.filesystemError("Conversion was cancelled.") }
        self.writer = writer
        self.reader = reader
        defer { self.writer = nil; self.reader = nil }

        guard writer.startWriting() else {
            throw ConversionError.filesystemError(writer.error?.localizedDescription ?? "Could not start the video encoder.")
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw ConversionError.filesystemError(reader.error?.localizedDescription ?? "Could not read the source video.")
        }
        let sessionStart = options.timeRange?.start ?? .zero
        writer.startSession(atSourceTime: sessionStart)

        let totalSeconds = CMTimeGetSeconds(options.timeRange?.duration ?? fullDuration)
        let startSeconds = CMTimeGetSeconds(sessionStart)
        progress(0.05)
        let group = DispatchGroup()
        group.enter()
        Self.pump(videoInput, from: videoOutput, label: "video-transcode", onSample: { buffer in
            guard totalSeconds > 0 else { return }
            let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer)) - startSeconds
            progress(min(0.95, 0.05 + 0.9 * (seconds / totalSeconds)))
        }, completion: { group.leave() })
        if let audioPair {
            group.enter()
            Self.pump(audioPair.input, from: audioPair.output, label: "audio-transcode", completion: { group.leave() })
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: DispatchQueue(label: "transcode-done")) { continuation.resume() }
        }

        if cancelled || reader.status == .cancelled || writer.status == .cancelled {
            throw ConversionError.filesystemError("Conversion was cancelled.")
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw ConversionError.filesystemError(reader.error?.localizedDescription ?? "Could not decode the source video.")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ConversionError.filesystemError(writer.error?.localizedDescription ?? "Video encoding did not complete.")
        }
        progress(1.0)
        // Not URL.resourceValues: it caches per URL instance, so a re-encode
        // to the same path would report the previous file's size
        let bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        return Result(bytes: bytes, rateMode: rateMode, hdr: hdr, seconds: totalSeconds, audioBitRate: audioBitRate)
    }

    // Encodes, then re-encodes at a bitrate scaled by the overshoot while the
    // file is still over the budget. Two retries land within a few percent
    // even on clips short enough for the first keyframe to dominate
    @discardableResult
    public func run(
        fittingUnder maxBytes: Int64,
        sourceURL: URL,
        destination: URL,
        options: Options,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Result {
        var options = options
        var result = try await run(sourceURL: sourceURL, destination: destination, options: options, progress: progress)
        var attempts = 0
        while result.bytes > maxBytes, attempts < 2, result.seconds > 0 {
            let overallBitRate = Double(result.bytes) * 8 / result.seconds
            let scaled = overallBitRate * Double(maxBytes) / Double(result.bytes) * 0.95 - Double(result.audioBitRate)
            options.rateMode = .averageBitRate(max(100_000, Int(scaled)))
            try? FileManager.default.removeItem(at: destination)
            result = try await run(sourceURL: sourceURL, destination: destination, options: options, progress: progress)
            attempts += 1
        }
        return result
    }

    // Feed one reader output into one writer input until the track ends or
    // the writer stops accepting data
    private static func pump(
        _ input: AVAssetWriterInput,
        from output: AVAssetReaderOutput,
        label: String,
        onSample: @escaping @Sendable (CMSampleBuffer) -> Void = { _ in },
        completion: @escaping @Sendable () -> Void
    ) {
        var finished = false
        input.requestMediaDataWhenReady(on: DispatchQueue(label: label)) {
            guard !finished else { return }
            while input.isReadyForMoreMediaData {
                guard let buffer = output.copyNextSampleBuffer(), input.append(buffer) else {
                    finished = true
                    input.markAsFinished()
                    completion()
                    return
                }
                onSample(buffer)
            }
        }
    }
}

// Projects a clip's encoded size from a short slice taken from its middle,
// so the estimate reflects the actual footage instead of a formula
public enum VideoSizeProbe {
    static let sliceSeconds = 2.5

    private actor Cache {
        var entries: [String: Int64] = [:]
        func get(_ key: String) -> Int64? { entries[key] }
        func set(_ key: String, _ value: Int64) { entries[key] = value }
    }
    private static let cache = Cache()

    public static func projectedBytes(
        sourceURL: URL,
        format: OutputFormat,
        preset: String,
        rateMode: VideoRateMode? = nil
    ) async throws -> Int64 {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = "\(sourceURL.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(format.rawValue)|\(preset)|\(String(describing: rateMode))"
        if let cached = await cache.get(key) { return cached }

        let asset = AVURLAsset(url: sourceURL)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration > 0, duration.isFinite else { throw ConversionError.unreadableInput }
        let slice = min(sliceSeconds, duration)
        let start = max(0, (duration - slice) / 2)
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: slice, preferredTimescale: 600)
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .notDirectory)
            .appendingPathExtension(format.preferredExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let transcoder = VideoTranscoder()
        let result = try await transcoder.run(
            sourceURL: sourceURL,
            destination: tempURL,
            options: VideoTranscoder.Options(format: format, preset: preset, rateMode: rateMode, timeRange: range, includeAudio: false)
        )
        let videoBytes = Double(result.bytes) * duration / slice

        var audioBytes = 0.0
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            var channels = 2
            if let description = try await audioTrack.load(.formatDescriptions).first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
               asbd.mChannelsPerFrame > 0 {
                channels = min(2, Int(asbd.mChannelsPerFrame))
            }
            audioBytes = Double(VideoRateModel.audioBitRate(channels: channels)) / 8 * duration
        }
        let projected = Int64(videoBytes + audioBytes)
        await cache.set(key, projected)
        return projected
    }
}
