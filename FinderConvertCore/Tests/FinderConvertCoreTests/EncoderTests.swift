import AVFoundation
import CoreGraphics
import XCTest
@testable import FinderConvertCore

// Pushes the bundled sample picture through every encoder path, so an
// encoder setting that a future macOS rejects fails here, not on a user's
// first conversion
final class EncoderTests: XCTestCase {
    private var sample: CGImage {
        get throws { try XCTUnwrap(QualityPreviewRenderer.sample()) }
    }

    // A one-second H.264 movie built from the sample, for transcoder tests
    private func makeMovie(seconds: Double = 1.0, withAudio: Bool = false) async throws -> URL {
        let image = try sample
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: image.width, AVVideoHeightKey: image.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: image.width, kCVPixelBufferHeightKey as String: image.height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool)
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = try XCTUnwrap(CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer), width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        // Pan across the picture so every frame carries real motion; a
        // static clip is one keyframe and says nothing about rate control
        let frames = Int(seconds * 30)
        for frame in 0..<frames {
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let shift = (frame * 6) % image.width
            context.draw(image, in: CGRect(x: -shift, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: image.width - shift, y: 0, width: image.width, height: image.height))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        return url
    }

    private func frameCount(_ url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        // Passthrough readers also hand out empty marker buffers, so count
        // samples rather than buffers
        var count = 0
        while let buffer = output.copyNextSampleBuffer() { count += CMSampleBufferGetNumSamples(buffer) }
        return count
    }

    func testEveryVideoLevelEncodesInBothRateModes() async throws {
        let source = try await makeMovie()
        defer { try? FileManager.default.removeItem(at: source) }
        for format in [OutputFormat.mp4, .mov, .hevc] {
            for preset in ["highest", "high", "medium", "low"] {
                let codec: AVVideoCodecType = format == .hevc ? .hevc : .h264
                let bitRate = VideoRateModel.targetBitRate(preset: preset, width: 640, height: 400, frameRate: 30, codec: codec)
                for mode in [VideoRateMode.constantQuality(VideoRateModel.encoderQuality(for: preset)), .averageBitRate(bitRate)] {
                    if case .constantQuality = mode,
                       !VideoRateModel.supportsConstantQuality(codec: codec, width: 640, height: 400) { continue }
                    let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(format.preferredExtension)")
                    defer { try? FileManager.default.removeItem(at: destination) }
                    let result = try await VideoTranscoder().run(
                        sourceURL: source, destination: destination,
                        options: VideoTranscoder.Options(format: format, preset: preset, rateMode: mode)
                    )
                    XCTAssertGreaterThan(result.bytes, 1_000, "\(format) \(preset) \(mode)")
                    XCTAssertEqual(result.rateMode, mode)
                    let frames = try await frameCount(destination)
                    XCTAssertEqual(frames, 30, "\(format) \(preset) \(mode) dropped frames")
                }
            }
        }
    }

    func testTimeRangeSliceEncodesOnlyThatSlice() async throws {
        let source = try await makeMovie(seconds: 2)
        defer { try? FileManager.default.removeItem(at: source) }
        let sourceFrames = try await frameCount(source)
        XCTAssertEqual(sourceFrames, 60, "fixture frame count")
        let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: destination) }
        let range = CMTimeRange(start: CMTime(seconds: 0.5, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        try await VideoTranscoder().run(sourceURL: source, destination: destination,
                                        options: VideoTranscoder.Options(format: .mp4, preset: "medium", timeRange: range))
        let frames = try await frameCount(destination)
        XCTAssertEqual(frames, 30)
        let duration = CMTimeGetSeconds(try await AVURLAsset(url: destination).load(.duration))
        XCTAssertEqual(duration, 1.0, accuracy: 0.05)
    }

    func testSizeProbeProjectsWholeClip() async throws {
        let source = try await makeMovie(seconds: 2)
        defer { try? FileManager.default.removeItem(at: source) }
        let projected = try await VideoSizeProbe.projectedBytes(sourceURL: source, format: .mp4, preset: "medium")
        let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: destination) }
        let actual = try await VideoTranscoder().run(sourceURL: source, destination: destination,
                                                     options: VideoTranscoder.Options(format: .mp4, preset: "medium"))
        // Static footage with keyframe-heavy slices: within a factor of two
        // is what the probe promises, real footage lands within a few percent
        XCTAssertGreaterThan(projected, actual.bytes / 2)
        XCTAssertLessThan(projected, actual.bytes * 2)
    }

    func testFittingBitRateLandsUnderBudget() async throws {
        let source = try await makeMovie(seconds: 4)
        defer { try? FileManager.default.removeItem(at: source) }
        let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: destination) }
        let full = try await VideoTranscoder().run(sourceURL: source, destination: destination,
                                                   options: VideoTranscoder.Options(format: .mp4, preset: "highest"))
        try? FileManager.default.removeItem(at: destination)
        let budget = full.bytes / 2
        let bitRate = VideoRateModel.bitRate(fitting: budget, duration: 4, audioBitRate: 0)
        let result = try await VideoTranscoder().run(fittingUnder: budget, sourceURL: source, destination: destination,
                                                     options: VideoTranscoder.Options(format: .mp4, preset: "high", rateMode: .averageBitRate(bitRate)))
        XCTAssertLessThanOrEqual(result.bytes, budget)
        XCTAssertGreaterThan(result.bytes, budget / 2, "should land near the budget, not far under it")
    }

    func testQualityPreviewRendersEveryLossyFormat() async throws {
        for format in [OutputFormat.jpeg, .heic, .avif, .webp, .mp4, .mov, .hevc] {
            let preview = try await QualityPreviewRenderer.render(format: format, quality: 0.5, videoPreset: "medium")
            XCTAssertEqual(preview.encoded.width, preview.original.width, "\(format)")
            XCTAssertEqual(preview.encoded.height, preview.original.height, "\(format)")
            if format.supportsQuality {
                XCTAssertGreaterThan(preview.encodedBytes, 0, "\(format)")
            }
        }
    }

    func testImageFitHoldsEveryFormatUnderBudget() async throws {
        let image = try sample
        let engine = NativeImageConversionEngine()
        for format in [OutputFormat.jpeg, .heic, .avif, .webp, .png, .gif, .bmp, .tiff] {
            let full = try await engine.encode(image, format: format, quality: 0.9, metadata: [:])
            let budget = max(4_000, full.count / 4)
            let fitted = try await engine.fit(image, format: format, startQuality: 0.9, metadata: [:], under: budget)
            XCTAssertLessThanOrEqual(fitted.count, budget, "\(format) \(fitted.count) > \(budget)")
        }
    }

    func testPresetJSONWithoutNewFieldsStillDecodes() throws {
        let legacy = Data(#"{"jpegQuality":0.7,"resizePercent":50}"#.utf8)
        let preset = try JSONDecoder().decode(PresetSettings.self, from: legacy)
        XCTAssertEqual(preset.resizePercent, 50)
        XCTAssertNil(preset.maxLongestEdge)
    }
}
