import AudioToolbox
import AVFoundation
import CLame
import Foundation
import OSLog

public actor AudioConversionEngine: ConversionEngine {
    public let identifier = "com.finderconvert.engine.audio.native"
    private let logger = Logger(subsystem: "FinderConvert", category: "audio-engine")
    private let naming = OutputNamingStrategy()
    private var activeExports: [UUID: AVAssetExportSession] = [:]

    public init() {}

    private static let supportedInputs: Set<DetectedFileType> = [.mp3, .m4a, .wav, .aiff, .flac, .ogg]
    private static let supportedOutputs: Set<OutputFormat> = [.mp3, .m4a, .wav, .aiff, .flac]

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

        let access = SecurityScopedAccess(url: sourceURL)
        let inputType = try FileTypeDetector().detect(url: sourceURL).detectedType
        guard supports(input: inputType, output: job.requestedOutput) else {
            throw ConversionError.unsupportedOutput(job.requestedOutput)
        }

        let destinationURL = try naming.destinationURL(
            for: sourceURL,
            outputFormat: job.requestedOutput,
            policy: job.destinationPolicy
        )

        progress(0.1)

        switch job.requestedOutput {
        case .mp3:
            try await exportToMP3(source: sourceURL, destination: destinationURL, progress: progress)
        case .m4a:
            try await exportWithSession(
                source: sourceURL,
                destination: destinationURL,
                fileType: .m4a,
                jobID: job.id,
                progress: progress
            )
        case .wav, .aiff:
            try await exportWithAssetWriter(
                source: sourceURL,
                destination: destinationURL,
                output: job.requestedOutput,
                progress: progress
            )
        case .flac:
            try await exportToFLAC(
                source: sourceURL,
                destination: destinationURL,
                progress: progress
            )
        default:
            throw ConversionError.unsupportedOutput(job.requestedOutput)
        }

        _ = access
        progress(1.0)
        return ConversionResult(sourceURL: sourceURL, outputURL: destinationURL, outputFormat: job.requestedOutput)
    }

    public func cancel(jobID: UUID) async {
        activeExports[jobID]?.cancelExport()
    }

    // MARK: - MP3 via LAME

    private func exportToMP3(
        source: URL,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ConversionError.filesystemError("No audio track found in source file.")
        }

        let sampleRate = PreferencesManager.shared.audioSampleRate(for: .mp3)
        let bitrate = PreferencesManager.shared.audioBitrate(for: .mp3)

        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(readerOutput)
        guard reader.startReading() else {
            throw ConversionError.filesystemError(reader.error?.localizedDescription ?? "Failed to read audio.")
        }

        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        // Initialize LAME
        guard let lame = lame_init() else {
            throw ConversionError.filesystemError("Failed to initialize MP3 encoder.")
        }
        lame_set_in_samplerate(lame, Int32(sampleRate))
        lame_set_num_channels(lame, 2)
        lame_set_brate(lame, Int32(bitrate / 1000))
        lame_set_quality(lame, 2) // 0=best, 9=fastest
        lame_set_mode(lame, JOINT_STEREO)
        lame_init_params(lame)

        // Open output file
        guard let outFile = fopen(destination.path, "wb") else {
            lame_close(lame)
            throw ConversionError.filesystemError("Could not create output MP3 file.")
        }

        let mp3BufSize = 8640
        let mp3Buf = UnsafeMutablePointer<UInt8>.allocate(capacity: mp3BufSize)
        defer {
            mp3Buf.deallocate()
            fclose(outFile)
            lame_close(lame)
        }

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

            var dataPointer: UnsafeMutablePointer<Int8>?
            var length = 0
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            guard let rawData = dataPointer else { continue }

            // Interleaved 16-bit PCM
            let pcmData = UnsafeRawPointer(rawData).bindMemory(to: Int16.self, capacity: numSamples * 2)

            let written = lame_encode_buffer_interleaved(lame, UnsafeMutablePointer(mutating: pcmData), Int32(numSamples), mp3Buf, Int32(mp3BufSize))

            if written > 0 {
                fwrite(mp3Buf, 1, Int(written), outFile)
            }

            // Progress
            let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if totalSeconds > 0 {
                let p = min(0.9, 0.1 + 0.8 * (CMTimeGetSeconds(ts) / totalSeconds))
                progress(p)
            }
        }

        // Flush remaining MP3 data
        let flushed = lame_encode_flush(lame, mp3Buf, Int32(mp3BufSize))
        if flushed > 0 {
            fwrite(mp3Buf, 1, Int(flushed), outFile)
        }
    }

    private func exportWithSession(
        source: URL,
        destination: URL,
        fileType: AVFileType,
        jobID: UUID,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ConversionError.filesystemError("Could not create audio export session.")
        }

        exportSession.outputFileType = fileType
        exportSession.outputURL = destination

        self.activeExports[jobID] = exportSession
        defer { self.activeExports.removeValue(forKey: jobID) }

        await exportSession.export()

        if let error = exportSession.error {
            throw ConversionError.filesystemError(error.localizedDescription)
        }
        guard exportSession.status == .completed else {
            throw ConversionError.filesystemError("Audio export did not complete. Status: \(exportSession.status.rawValue)")
        }
    }

    private func exportWithAssetWriter(
        source: URL,
        destination: URL,
        output: OutputFormat,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ConversionError.filesystemError("No audio track found in source file.")
        }

        let sampleRate = PreferencesManager.shared.audioSampleRate(for: output)
        let fileType: AVFileType
        let outputSettings: [String: Any]

        switch output {
        case .wav:
            fileType = .wav
            outputSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .aiff:
            fileType = .aiff
            outputSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ]
        default:
            throw ConversionError.unsupportedOutput(output)
        }

        let writer = try AVAssetWriter(outputURL: destination, fileType: fileType)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerOutputSettings)
        reader.add(readerOutput)

        guard writer.startWriting() else {
            throw ConversionError.filesystemError(writer.error?.localizedDescription ?? "Failed to start audio writer.")
        }
        guard reader.startReading() else {
            throw ConversionError.filesystemError(reader.error?.localizedDescription ?? "Failed to start audio reader.")
        }

        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio-writer")) {
                while writerInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let currentSeconds = CMTimeGetSeconds(timestamp)
                    if totalSeconds > 0 {
                        let pct = min(0.9, 0.1 + 0.8 * (currentSeconds / totalSeconds))
                        progress(pct)
                    }
                    writerInput.append(sampleBuffer)
                }
            }
        }

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw ConversionError.filesystemError(writer.error?.localizedDescription ?? "Audio writer failed.")
        }
    }

    // MARK: - FLAC via ExtAudioFile (AudioToolbox)

    private func exportToFLAC(
        source: URL,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ConversionError.filesystemError("No audio track found in source file.")
        }

        let sampleRate = PreferencesManager.shared.audioSampleRate(for: .flac)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        // Read source as PCM via AVAssetReader
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(readerOutput)
        guard reader.startReading() else {
            throw ConversionError.filesystemError(reader.error?.localizedDescription ?? "Failed to read audio.")
        }

        // Setup ExtAudioFile for FLAC output
        var inputASBD = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var outputASBD = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatFLAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 0,
            mBytesPerFrame: 0,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        // Fill in output ASBD defaults
        var outputASBDSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let fillStatus = AudioFormatGetProperty(
            kAudioFormatProperty_FormatInfo,
            0, nil,
            &outputASBDSize, &outputASBD
        )
        if fillStatus != noErr {
            logger.warning("AudioFormatGetProperty returned \(fillStatus), proceeding with manual ASBD.")
        }

        var extAudioFile: ExtAudioFileRef?
        let destCF = destination as CFURL
        let createStatus = ExtAudioFileCreateWithURL(
            destCF,
            kAudioFileFLACType,
            &outputASBD,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &extAudioFile
        )

        guard createStatus == noErr, let outputFile = extAudioFile else {
            throw ConversionError.filesystemError("Failed to create FLAC output file (status: \(createStatus)).")
        }

        defer { ExtAudioFileDispose(outputFile) }

        // Set client data format (the PCM format we'll feed it)
        var status = ExtAudioFileSetProperty(
            outputFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &inputASBD
        )
        guard status == noErr else {
            throw ConversionError.filesystemError("Failed to set FLAC client format (status: \(status)).")
        }

        // Write PCM buffers to FLAC
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

            var dataPointer: UnsafeMutablePointer<Int8>?
            var length = 0
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            guard let rawData = dataPointer else { continue }

            var audioBuffer = AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(length),
                mData: UnsafeMutableRawPointer(rawData)
            )
            var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)

            status = ExtAudioFileWrite(outputFile, UInt32(numSamples), &bufferList)
            if status != noErr {
                throw ConversionError.filesystemError("Failed to write FLAC data (status: \(status)).")
            }

            // Progress
            let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if totalSeconds > 0 {
                let p = min(0.9, 0.1 + 0.8 * (CMTimeGetSeconds(ts) / totalSeconds))
                progress(p)
            }
        }
    }
}
