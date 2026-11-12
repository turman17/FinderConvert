import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FinderConvertCore

// Same-format compression: output naming, the never-bigger guard, and the
// Finder menu estimates. Runs with the default settings (JPEG quality 0.9)
final class CompressionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "compression-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeSample(named name: String, type: UTType, quality: Double) throws -> URL {
        let image = try XCTUnwrap(QualityPreviewRenderer.sample())
        let url = directory.appending(path: name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testOnlyFormatsWithSameFormatEncodersCompress() {
        for type: DetectedFileType in [.jpeg, .png, .tiff, .gif, .bmp, .mov, .mp3, .wav, .flac] {
            XCTAssertTrue(Compression.isCompressible(type), type.rawValue)
        }
        for type: DetectedFileType in [.svg, .ogg, .webm, .pdf] {
            XCTAssertFalse(Compression.isCompressible(type), type.rawValue)
        }
    }

    func testCompressWritesSmallerCopyBesideSource() async throws {
        let source = try writeSample(named: "photo.jpg", type: .jpeg, quality: 1.0)
        let result = try await QuickActionConversionService().compress(urls: [source])

        let output = try XCTUnwrap(result.successes.first?.outputURL)
        XCTAssertEqual(output.lastPathComponent, "photo compressed.jpg")
        XCTAssertLessThan(try XCTUnwrap(Compression.fileSize(output)), try XCTUnwrap(Compression.fileSize(source)))
        XCTAssertTrue(result.skipped.isEmpty)
    }

    func testCompressKeepsOriginalWhenReencodeIsNotSmaller() async throws {
        let source = try writeSample(named: "tiny.jpg", type: .jpeg, quality: 0.1)
        let result = try await QuickActionConversionService().compress(urls: [source])

        XCTAssertEqual(result.skipped, [source])
        XCTAssertTrue(result.successes.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, ["tiny.jpg"])
    }

    func testCompressRejectsSelectionWithNothingCompressible() async throws {
        let source = directory.appending(path: "notes.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        do {
            _ = try await QuickActionConversionService().compress(urls: [source])
            XCTFail("A text file should not compress")
        } catch ConversionError.unsupportedSelection {}
    }

    // Runs the body with a built-in preset applied, restoring settings after
    private func withPreset<T>(_ name: String, _ body: () async throws -> T) async throws -> T {
        let prefs = PreferencesManager.shared
        let snapshot = try XCTUnwrap(prefs.captureSettingsSnapshotData())
        defer { prefs.restoreSettingsSnapshot(snapshot) }
        prefs.applyPresetValues(try XCTUnwrap(prefs.presetSettings(named: name)))
        return try await body()
    }

    func testPaletteCompressionKeepsTransparency() async throws {
        // Opaque left half, fading alpha on the right
        let width = 256, height = 128
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(try XCTUnwrap(QualityPreviewRenderer.sample()), in: CGRect(x: 0, y: 0, width: width, height: height))
        for x in (width / 2)..<width {
            context.clear(CGRect(x: x, y: 0, width: 1, height: height))
            context.setFillColor(red: 0.2, green: 0.4, blue: 0.9, alpha: CGFloat(width - x) / CGFloat(width / 2))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        let image = try XCTUnwrap(context.makeImage())

        let data = try PngQuantizer.encode(image, colors: 64, dpi: (x: 144, y: 144))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyDPIWidth] as? Double, 144)
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        // Read back alpha: opaque stays opaque, the fade survives
        let check = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        check.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try XCTUnwrap(check.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        let row = (height / 2) * width * 4
        XCTAssertEqual(pixels[row + 10 * 4 + 3], 255)
        let fadeMid = Int(pixels[row + (width * 3 / 4) * 4 + 3])
        XCTAssertEqual(Double(fadeMid), 127, accuracy: 24)
        XCTAssertLessThan(Int(pixels[row + (width - 1) * 4 + 3]), 24)
    }

    func testPNGAndTIFFShrinkLosslessOrWithPalette() async throws {
        let png = try writeSample(named: "shot.png", type: .png, quality: 1.0)
        let tiff = try writeSample(named: "scan.tiff", type: .tiff, quality: 1.0)
        let result = try await withPreset("Web Optimized") {
            try await QuickActionConversionService().compress(urls: [png, tiff])
        }
        XCTAssertEqual(Set(result.successes.map(\.outputURL.lastPathComponent)), ["shot compressed.png", "scan compressed.tiff"])
    }

    func testAnimatedGIFIsLeftAlone() async throws {
        let url = directory.appending(path: "anim.gif")
        let image = try XCTUnwrap(QualityPreviewRenderer.sample())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let result = try await withPreset("Thumbnail") { try await QuickActionConversionService().compress(urls: [url]) }
        XCTAssertEqual(result.skipped, [url])
    }

    // Two seconds of a stereo tone in the given file format
    private func writeTone(named name: String, settings: [String: Any]) throws -> URL {
        let url = directory.appending(path: name)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88200))
        buffer.frameLength = 88200
        for channel in 0..<2 {
            for frame in 0..<88200 {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44100) * 0.5)
            }
        }
        try file.write(from: buffer)
        return url
    }

    func testPodcastPresetMakesWAVMono() async throws {
        let wav = try writeTone(named: "voice.wav", settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
        ])
        let result = try await withPreset("Podcast") { try await QuickActionConversionService().compress(urls: [wav]) }
        let output = try XCTUnwrap(result.successes.first?.outputURL)
        let format = try AVAudioFile(forReading: output).fileFormat
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.sampleRate, 22050)
    }

    func testM4AUsesTheBitrateSetting() async throws {
        let m4a = try writeTone(named: "song.m4a", settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256000,
        ])
        let result = try await withPreset("Podcast") { try await QuickActionConversionService().compress(urls: [m4a]) }
        let output = try XCTUnwrap(result.successes.first?.outputURL, "64 kbps re-encode of a 256 kbps file should be smaller")
        XCTAssertLessThan(try XCTUnwrap(Compression.fileSize(output)), try XCTUnwrap(Compression.fileSize(m4a)) / 2)
    }

    func testMenuEstimateCoversCurrentSettingsAndPresets() async throws {
        let source = try writeSample(named: "photo.jpg", type: .jpeg, quality: 1.0)
        let computed = await CompressionEstimate.compute(urls: [source], presetNames: ["Email Friendly"])
        let estimate = try XCTUnwrap(computed)

        XCTAssertEqual(estimate.sourceBytes, Compression.fileSize(source))
        let current = try XCTUnwrap(estimate.estimates[""])
        let email = try XCTUnwrap(estimate.estimates["Email Friendly"])
        XCTAssertLessThanOrEqual(current, estimate.sourceBytes)
        XCTAssertLessThan(email, current)
    }
}
