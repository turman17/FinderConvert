import Foundation

// @unchecked Sendable: UserDefaults is thread-safe but not marked Sendable in Swift 6
public struct PreferencesManager: @unchecked Sendable {
    public static let shared = PreferencesManager()
    
    private let defaults: UserDefaults
    private let defaultFormats: [OutputFormat] = [.jpeg, .png, .heic, .tiff, .gif, .bmp, .ico, .avif, .webp, .mp4, .mov, .hevc, .mp3, .m4a, .wav, .aiff, .flac, .pdf, .rtf, .html, .txt, .csv, .tsv, .xlsx, .docx]
    private let key = "enabledFormats"

    public init(defaults: UserDefaults = UserDefaults(suiteName: "group.com.finderconvert.app.shared") ?? .standard) {
        self.defaults = defaults

        if !defaults.bool(forKey: "v11_defaults_set") {
            defaults.set(defaultFormats.map { $0.rawValue }, forKey: key)
            defaults.set(true, forKey: "v11_defaults_set")
        }
    }
    
    public var enabledFormats: [OutputFormat] {
        get {
            guard let saved = defaults.array(forKey: key) as? [String] else {
                return defaultFormats
            }
            return saved.compactMap { OutputFormat(rawValue: $0) }
        }
        nonmutating set {
            let strings = newValue.map { $0.rawValue }
            defaults.set(strings, forKey: key)
        }
    }

    // Per-format quality (0.1 – 1.0). Only meaningful for lossy formats.
    public func quality(for format: OutputFormat) -> Double {
        let val = defaults.double(forKey: "quality_\(format.rawValue)")
        return val > 0 ? val : format.defaultQuality
    }

    public func setQuality(_ value: Double, for format: OutputFormat) {
        defaults.set(value, forKey: "quality_\(format.rawValue)")
    }

    // Per-format resize percent (1–100). 100 = no resize.
    public func resizePercent(for format: OutputFormat) -> Int {
        let val = defaults.integer(forKey: "resize_\(format.rawValue)")
        return val > 0 ? val : 100
    }

    public func setResizePercent(_ value: Int, for format: OutputFormat) {
        defaults.set(value, forKey: "resize_\(format.rawValue)")
    }

    // Video export preset: "highest", "high", "medium", "low"
    public func videoPreset(for format: OutputFormat) -> String {
        defaults.string(forKey: "videoPreset_\(format.rawValue)") ?? "highest"
    }

    public func setVideoPreset(_ value: String, for format: OutputFormat) {
        defaults.set(value, forKey: "videoPreset_\(format.rawValue)")
    }

    // Audio sample rate: 44100, 22050, 48000
    public func audioSampleRate(for format: OutputFormat) -> Int {
        let val = defaults.integer(forKey: "audioSampleRate_\(format.rawValue)")
        return val > 0 ? val : 44100
    }

    public func setAudioSampleRate(_ value: Int, for format: OutputFormat) {
        defaults.set(value, forKey: "audioSampleRate_\(format.rawValue)")
    }

    // Audio bitrate for AAC: 64000, 128000, 192000, 256000
    public func audioBitrate(for format: OutputFormat) -> Int {
        let val = defaults.integer(forKey: "audioBitrate_\(format.rawValue)")
        return val > 0 ? val : 128000
    }

    public func setAudioBitrate(_ value: Int, for format: OutputFormat) {
        defaults.set(value, forKey: "audioBitrate_\(format.rawValue)")
    }

    // Per-format metadata stripping (EXIF/GPS removal)
    public func stripMetadata(for format: OutputFormat) -> Bool {
        defaults.bool(forKey: "stripMetadata_\(format.rawValue)")
    }

    public func setStripMetadata(_ value: Bool, for format: OutputFormat) {
        defaults.set(value, forKey: "stripMetadata_\(format.rawValue)")
    }

    // Batch rename suffix
    public var renameSuffix: String {
        get {
            let val = defaults.string(forKey: "renameSuffix")
            // Return stored value if key exists, even if empty
            return val ?? " converted"
        }
        nonmutating set {
            defaults.set(newValue, forKey: "renameSuffix")
        }
    }

    // Custom output folder (nil = beside source)
    public var customOutputFolder: URL? {
        get {
            guard let path = defaults.string(forKey: "customOutputFolder"), !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path)
        }
        nonmutating set {
            defaults.set(newValue?.path ?? "", forKey: "customOutputFolder")
        }
    }

    public var useCustomOutputFolder: Bool {
        get { defaults.bool(forKey: "useCustomOutputFolder") }
        nonmutating set { defaults.set(newValue, forKey: "useCustomOutputFolder") }
    }

    // Preset profiles
    public func savePreset(name: String, settings: PresetSettings) {
        var presets = loadAllPresets()
        presets[name] = settings
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: "conversionPresets")
        }
    }

    public func loadPreset(name: String) -> PresetSettings? {
        loadAllPresets()[name]
    }

    public func loadAllPresets() -> [String: PresetSettings] {
        guard let data = defaults.data(forKey: "conversionPresets") else { return [:] }
        return (try? JSONDecoder().decode([String: PresetSettings].self, from: data)) ?? [:]
    }

    public func deletePreset(name: String) {
        var presets = loadAllPresets()
        presets.removeValue(forKey: name)
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: "conversionPresets")
        }
    }

    public func applyPreset(_ preset: PresetSettings) {
        if let q = preset.jpegQuality { setQuality(q, for: .jpeg) }
        if let q = preset.heicQuality { setQuality(q, for: .heic) }
        if let q = preset.webpQuality { setQuality(q, for: .webp) }
        if let q = preset.avifQuality { setQuality(q, for: .avif) }
        if let r = preset.resizePercent {
            for f in OutputFormat.allCases where f.supportsResize {
                setResizePercent(r, for: f)
            }
        }
        if let p = preset.videoPreset {
            for f in OutputFormat.allCases where f.supportsVideoQuality {
                setVideoPreset(p, for: f)
            }
        }
        if let s = preset.stripMetadata {
            for f in OutputFormat.allCases where f.category == .image {
                setStripMetadata(s, for: f)
            }
        }
        if let b = preset.audioBitrate {
            for f in OutputFormat.allCases where f.supportsAudioBitrate {
                setAudioBitrate(b, for: f)
            }
        }
    }

    // Onboarding
    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        nonmutating set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    // Legacy
    public var jpegQuality: Double {
        get { quality(for: .jpeg) }
        nonmutating set { setQuality(newValue, for: .jpeg) }
    }

    public var imageResizePercent: Int {
        get {
            let val = defaults.integer(forKey: "imageResizePercent")
            return val > 0 ? val : 100
        }
        nonmutating set {
            defaults.set(newValue, forKey: "imageResizePercent")
        }
    }
}

public struct PresetSettings: Codable, Sendable {
    public var jpegQuality: Double?
    public var heicQuality: Double?
    public var webpQuality: Double?
    public var avifQuality: Double?
    public var resizePercent: Int?
    public var videoPreset: String?
    public var stripMetadata: Bool?
    public var audioBitrate: Int?
    public var description: String?

    public init(jpegQuality: Double? = nil, heicQuality: Double? = nil, webpQuality: Double? = nil, avifQuality: Double? = nil,
                resizePercent: Int? = nil, videoPreset: String? = nil, stripMetadata: Bool? = nil, audioBitrate: Int? = nil, description: String? = nil) {
        self.jpegQuality = jpegQuality
        self.heicQuality = heicQuality
        self.webpQuality = webpQuality
        self.avifQuality = avifQuality
        self.resizePercent = resizePercent
        self.videoPreset = videoPreset
        self.stripMetadata = stripMetadata
        self.audioBitrate = audioBitrate
        self.description = description
    }

    public static let builtIn: [(name: String, icon: String, settings: PresetSettings)] = [
        // Image presets
        ("Web Optimized", "globe", PresetSettings(
            jpegQuality: 0.75, heicQuality: 0.75, webpQuality: 0.75, avifQuality: 0.7,
            resizePercent: 75, stripMetadata: true,
            description: "Balanced quality and size for websites. Strips metadata."
        )),
        ("Email Friendly", "envelope", PresetSettings(
            jpegQuality: 0.6, heicQuality: 0.6, webpQuality: 0.6, avifQuality: 0.5,
            resizePercent: 50, stripMetadata: true,
            description: "Small files for email attachments. 50% resize, strips metadata."
        )),
        ("Social Media", "person.2", PresetSettings(
            jpegQuality: 0.8, heicQuality: 0.8, webpQuality: 0.8,
            resizePercent: 75, stripMetadata: true,
            description: "Good quality at manageable size. Strips GPS/EXIF data for privacy."
        )),
        ("Maximum Quality", "star", PresetSettings(
            jpegQuality: 1.0, heicQuality: 1.0, webpQuality: 1.0, avifQuality: 1.0,
            resizePercent: 100, stripMetadata: false,
            description: "Highest quality, original size, metadata preserved."
        )),
        ("Archive / Lossless", "archivebox", PresetSettings(
            jpegQuality: 1.0, heicQuality: 1.0, webpQuality: 1.0, avifQuality: 1.0,
            resizePercent: 100, stripMetadata: false,
            description: "Best for archival. Use with PNG or TIFF for truly lossless output."
        )),
        ("Thumbnail", "photo.on.rectangle", PresetSettings(
            jpegQuality: 0.7, heicQuality: 0.7, webpQuality: 0.7,
            resizePercent: 25, stripMetadata: true,
            description: "Tiny previews at 25% size. Great for galleries and catalogs."
        )),
        ("Print Ready", "printer", PresetSettings(
            jpegQuality: 0.95, heicQuality: 0.95,
            resizePercent: 100, stripMetadata: false,
            description: "Near-lossless quality at full resolution. Keeps metadata for color profiles."
        )),
        // Video presets
        ("Highest Quality", "film", PresetSettings(
            videoPreset: "highest",
            description: "Maximum video quality. Largest file size."
        )),
        ("Balanced", "film.stack", PresetSettings(
            videoPreset: "high",
            description: "High quality with reasonable file size."
        )),
        ("Small File", "arrow.down.circle", PresetSettings(
            videoPreset: "medium",
            description: "Medium quality. Good for sharing and uploads."
        )),
        ("Compressed", "archivebox", PresetSettings(
            videoPreset: "low",
            description: "Smallest file size. Lower quality."
        )),
        // Audio presets
        ("HQ Audio", "headphones", PresetSettings(
            audioBitrate: 256000,
            description: "256 kbps. Near-CD quality for music."
        )),
        ("Standard Audio", "speaker.wave.2", PresetSettings(
            audioBitrate: 128000,
            description: "128 kbps. Good balance of quality and size."
        )),
        ("Podcast", "mic", PresetSettings(
            audioBitrate: 64000,
            description: "64 kbps. Optimized for voice recordings."
        )),
    ]
}

