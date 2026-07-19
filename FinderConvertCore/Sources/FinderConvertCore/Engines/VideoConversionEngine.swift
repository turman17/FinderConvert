import AVFoundation
import CLame
import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

public actor VideoConversionEngine: ConversionEngine {
    public let identifier = "com.finderconvert.engine.video.native"
    private let logger = Logger(subsystem: "FinderConvert", category: "video-engine")
    private let naming = OutputNamingStrategy()
    private var activeExports: [UUID: AVAssetExportSession] = [:]

    public init() {}

    public nonisolated func supports(input: DetectedFileType, output: OutputFormat) -> Bool {
        switch input {
        case .mp4, .mov, .webm:
            switch output {
            case .mp4, .mov, .hevc, .gif, .mp3, .m4a, .wav, .aiff, .flac:
                return true
            default:
                return false
            }
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
        let inputType = try FileTypeDetector().detect(url: sourceURL).detectedType
        guard self.supports(input: inputType, output: job.requestedOutput) else {
            throw ConversionError.unsupportedOutput(job.requestedOutput)
        }

        let destinationURL = try self.naming.destinationURL(
            for: sourceURL,
            outputFormat: job.requestedOutput,
            policy: job.destinationPolicy
        )

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            do {
                try FileManager.default.removeItem(at: destinationURL)
            } catch {
                logger.error("Failed to remove existing file at destination: \(error.localizedDescription, privacy: .public)")
                throw ConversionError.invalidDestination
            }
        }

        let asset = AVURLAsset(url: sourceURL)

        // Extract audio track from video
        if job.requestedOutput == .mp3 || job.requestedOutput == .m4a || job.requestedOutput == .wav || job.requestedOutput == .aiff || job.requestedOutput == .flac {
            // Verify the video has an audio track
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if audioTracks.isEmpty {
                throw ConversionError.filesystemError("This video has no audio track. Try a video recorded with a microphone.")
            }
            try await extractAudio(from: asset, to: destinationURL, format: job.requestedOutput, progress: progress)
            _ = access
            return ConversionResult(sourceURL: sourceURL, outputURL: destinationURL, outputFormat: job.requestedOutput)
        }

        if job.requestedOutput == .gif {
            try await exportAsAnimatedGIF(asset: asset, destination: destinationURL, progress: progress)
            _ = access
            return ConversionResult(sourceURL: sourceURL, outputURL: destinationURL, outputFormat: job.requestedOutput)
        }

        let presetName: String
        if job.requestedOutput == .hevc {
            switch PreferencesManager.shared.videoPreset(for: .hevc) {
            case "low": presetName = AVAssetExportPresetHEVC1920x1080
            case "medium": presetName = AVAssetExportPresetHEVC1920x1080
            case "high": presetName = AVAssetExportPresetHEVC3840x2160
            default: presetName = AVAssetExportPresetHEVCHighestQuality
            }
        } else {
            switch PreferencesManager.shared.videoPreset(for: job.requestedOutput) {
            case "low": presetName = AVAssetExportPresetLowQuality
            case "medium": presetName = AVAssetExportPresetMediumQuality
            case "high": presetName = AVAssetExportPresetHighestQuality
            default: presetName = AVAssetExportPresetHighestQuality
            }
        }
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ConversionError.failedToEncodeImage(job.requestedOutput)
        }

        switch job.requestedOutput {
        case .mp4:
            exportSession.outputFileType = .mp4
        case .mov:
            exportSession.outputFileType = .mov
        case .hevc:
            exportSession.outputFileType = .mov
        default:
            throw ConversionError.unsupportedOutput(job.requestedOutput)
        }

        exportSession.outputURL = destinationURL

        self.activeExports[job.id] = exportSession
        defer { self.activeExports.removeValue(forKey: job.id) }

        await exportSession.export()
        _ = access

        if let error = exportSession.error {
            throw ConversionError.filesystemError(error.localizedDescription)
        }

        guard exportSession.status == .completed else {
            throw ConversionError.filesystemError("Export did not complete successfully. Status: \(exportSession.status.rawValue)")
        }

        return ConversionResult(sourceURL: sourceURL, outputURL: destinationURL, outputFormat: job.requestedOutput)
    }
    
    public func cancel(jobID: UUID) async {
        activeExports[jobID]?.cancelExport()
    }

    private func extractAudio(
        from asset: AVURLAsset,
        to destination: URL,
        format: OutputFormat,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if format == .m4a {
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw ConversionError.filesystemError("Could not create audio export session.")
            }
            session.outputFileType = .m4a
            session.outputURL = destination
            await session.export()
            if let error = session.error { throw ConversionError.filesystemError(error.localizedDescription) }
            guard session.status == .completed else {
                throw ConversionError.filesystemError("Audio extraction failed. Status: \(session.status.rawValue)")
            }
            return
        }

        if format == .mp3 {
            try await extractToMP3(from: asset, to: destination, progress: progress)
            return
        }

        // WAV/AIFF via AVAssetWriter
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ConversionError.filesystemError("No audio track found in video.")
        }

        let fileType: AVFileType = format == .aiff ? .aiff : .wav
        let isBigEndian = format == .aiff
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: isBigEndian,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let writer = try AVAssetWriter(outputURL: destination, fileType: fileType)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(readerOutput)

        guard writer.startWriting() else {
            throw ConversionError.filesystemError(writer.error?.localizedDescription ?? "Failed to start writer.")
        }
        guard reader.startReading() else {
            throw ConversionError.filesystemError(reader.error?.localizedDescription ?? "Failed to start reader.")
        }
        writer.startSession(atSourceTime: .zero)

        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio-extract")) {
                while writerInput.isReadyForMoreMediaData {
                    guard let buffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                    if totalSeconds > 0 {
                        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
                        progress(min(0.9, 0.1 + 0.8 * (t / totalSeconds)))
                    }
                    writerInput.append(buffer)
                }
            }
        }

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ConversionError.filesystemError(writer.error?.localizedDescription ?? "Audio extraction failed.")
        }
    }

    private func extractToMP3(from asset: AVURLAsset, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ConversionError.filesystemError("No audio track found in video.")
        }
        let sampleRate = 44100
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(output)
        guard reader.startReading() else { throw ConversionError.filesystemError("Failed to read audio track.") }

        let duration = try await asset.load(.duration)
        let totalSec = CMTimeGetSeconds(duration)
        let bitrate = PreferencesManager.shared.audioBitrate(for: .mp3)

        guard let lame = lame_init() else { throw ConversionError.filesystemError("Failed to init MP3 encoder.") }
        lame_set_in_samplerate(lame, Int32(sampleRate))
        lame_set_num_channels(lame, 2)
        lame_set_brate(lame, Int32(bitrate / 1000))
        lame_set_quality(lame, 2)
        lame_set_mode(lame, JOINT_STEREO)
        lame_init_params(lame)

        guard let outFile = fopen(destination.path, "wb") else { lame_close(lame); throw ConversionError.invalidDestination }
        let bufSize = 8640
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate(); fclose(outFile); lame_close(lame) }

        while let sb = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            let n = CMSampleBufferGetNumSamples(sb)
            var ptr: UnsafeMutablePointer<Int8>?; var len = 0
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
            guard let p = ptr else { continue }
            let pcm = UnsafeRawPointer(p).bindMemory(to: Int16.self, capacity: n * 2)
            let w = lame_encode_buffer_interleaved(lame, UnsafeMutablePointer(mutating: pcm), Int32(n), buf, Int32(bufSize))
            if w > 0 { fwrite(buf, 1, Int(w), outFile) }
            if totalSec > 0 { progress(min(0.9, 0.1 + 0.8 * CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)) / totalSec)) }
        }
        let f = lame_encode_flush(lame, buf, Int32(bufSize))
        if f > 0 { fwrite(buf, 1, Int(f), outFile) }
    }

    private func exportAsAnimatedGIF(
        asset: AVURLAsset,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let fps: Double = 10
        let maxFrames = 200
        let frameCount = min(maxFrames, Int(totalSeconds * fps))

        guard frameCount > 0 else {
            throw ConversionError.filesystemError("Video is too short to generate a GIF.")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 480, height: 480)

        let frameDelay = totalSeconds / Double(frameCount)

        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]

        guard let destination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            gifProperties as CFDictionary
        ) else {
            throw ConversionError.failedToEncodeImage(.gif)
        }

        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ]

        for i in 0..<frameCount {
            let time = CMTime(seconds: Double(i) * frameDelay, preferredTimescale: 600)
            let cgImage: CGImage
            do {
                let (image, _) = try await generator.image(at: time)
                cgImage = image
            } catch {
                logger.warning("Skipping frame \(i): \(error.localizedDescription, privacy: .public)")
                continue
            }

            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            progress(0.1 + 0.8 * Double(i) / Double(frameCount))
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.failedToEncodeImage(.gif)
        }
    }
}
