import Foundation

public enum AppGroup {
    // Team-ID-prefixed group: macOS authorizes it from the code signature
    // alone. The old "group."-style name could not be tied to the signing
    // team, so macOS 15+ showed an "access data from other apps" consent
    // prompt on every launch.
    public static let identifier = "YJ3UZ772GP.com.finderconvert.app.shared"
    private static let legacyIdentifier = "group.com.finderconvert.app.shared"
    private static let migrationFlag = "didMigrateFromLegacyGroupContainer"

    public static func defaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: identifier) ?? .standard
        // One-time settings/history migration out of the legacy container.
        // Main app only: the sandboxed extension can no longer read the old
        // container, and must not burn the shared migration flag
        if Bundle.main.bundleIdentifier == "com.finderconvert.app",
           !suite.bool(forKey: migrationFlag) {
            if let legacy = UserDefaults(suiteName: legacyIdentifier),
               let domain = legacy.persistentDomain(forName: legacyIdentifier) {
                for (key, value) in domain where suite.object(forKey: key) == nil {
                    suite.set(value, forKey: key)
                }
            }
            suite.set(true, forKey: migrationFlag)
        }
        return suite
    }
}

// @unchecked Sendable: UserDefaults is thread-safe but not marked Sendable in Swift 6
public struct PreferencesManager: @unchecked Sendable {
    public static let shared = PreferencesManager()

    private let defaults: UserDefaults
    private let defaultFormats: [OutputFormat] = [.jpeg, .png, .heic, .tiff, .gif, .bmp, .ico, .avif, .webp, .mp4, .mov, .hevc, .mp3, .m4a, .wav, .aiff, .flac, .pdf, .rtf, .html, .txt, .csv, .tsv, .xlsx, .docx]
    private let key = "enabledFormats"

    public init(defaults: UserDefaults = AppGroup.defaults()) {
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

    // Longest edge cap in pixels for image outputs (0 = none). Applied after
    // the percentage resize, so a 48 MP photo can be held to 2048 px without
    // touching small images
    public func maxLongestEdge(for format: OutputFormat) -> Int {
        max(0, defaults.integer(forKey: "maxEdge_\(format.rawValue)"))
    }

    public func setMaxLongestEdge(_ value: Int, for format: OutputFormat) {
        defaults.set(value, forKey: "maxEdge_\(format.rawValue)")
    }

    // Byte budget every output must fit under (0 = off). Images lower
    // quality, then dimensions; videos switch to a bitrate that fits
    public var maxOutputBytes: Int64 {
        get { Int64(defaults.integer(forKey: "maxOutputBytes")) }
        nonmutating set { defaults.set(Int(newValue), forKey: "maxOutputBytes") }
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

    // Channel count for WAV/AIFF/FLAC: 2 (stereo) or 1 (mono)
    public func audioChannels(for format: OutputFormat) -> Int {
        let val = defaults.integer(forKey: "audioChannels_\(format.rawValue)")
        return val > 0 ? val : 2
    }

    public func setAudioChannels(_ value: Int, for format: OutputFormat) {
        defaults.set(value, forKey: "audioChannels_\(format.rawValue)")
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

    // Visual style for Markdown → PDF/HTML conversion
    public var markdownStyle: MarkdownStyle {
        get { MarkdownStyle(rawValue: defaults.string(forKey: "markdownStyle") ?? "") ?? .modern }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "markdownStyle") }
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

    // Name of the currently applied preset (nil = none). While a preset is
    // active, the settings it replaced are kept as a baseline so it can be
    // unapplied.
    public var activePresetName: String? {
        defaults.string(forKey: "activePresetName")
    }

    public func applyPreset(_ preset: PresetSettings, named name: String? = nil) {
        // Capture the pre-preset settings once; applying another preset on
        // top keeps the original baseline so unapply always returns to the
        // user's own settings.
        if defaults.data(forKey: "presetBaseline") == nil,
           let data = try? JSONEncoder().encode(captureSnapshot()) {
            defaults.set(data, forKey: "presetBaseline")
        }

        applyPresetValues(preset)

        if let name {
            defaults.set(name, forKey: "activePresetName")
        } else {
            defaults.removeObject(forKey: "activePresetName")
        }
    }

    // Write a preset's values into the per-format settings without touching
    // the apply/unapply baseline bookkeeping. Used for temporary per-file
    // preset application during conversion.
    public func applyPresetValues(_ preset: PresetSettings) {
        if let q = preset.jpegQuality { setQuality(q, for: .jpeg) }
        if let q = preset.heicQuality { setQuality(q, for: .heic) }
        if let q = preset.webpQuality { setQuality(q, for: .webp) }
        if let q = preset.avifQuality { setQuality(q, for: .avif) }
        if let q = preset.pngQuality { setQuality(q, for: .png) }
        if let r = preset.resizePercent {
            for f in OutputFormat.allCases where f.supportsResize {
                setResizePercent(r, for: f)
            }
        }
        if let edge = preset.maxLongestEdge {
            for f in OutputFormat.allCases where f.supportsResize {
                setMaxLongestEdge(edge, for: f)
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
        // Sample rate and channels only for WAV/AIFF/FLAC: MP3 and AAC
        // shrink through the bitrate and keep their own sample rate
        for f in OutputFormat.allCases where f.supportsAudioChannels {
            if let rate = preset.audioSampleRate { setAudioSampleRate(rate, for: f) }
            if let channels = preset.audioChannels { setAudioChannels(channels, for: f) }
        }
    }

    // MARK: Temporary settings snapshots (per-file preset conversion)

    public func captureSettingsSnapshotData() -> Data? {
        try? JSONEncoder().encode(captureSnapshot())
    }

    public func restoreSettingsSnapshot(_ data: Data) {
        guard let snap = try? JSONDecoder().decode(FormatSettingsSnapshot.self, from: data) else { return }
        restore(snap)
    }

    // MARK: Built-in preset overrides (editable built-ins)

    public func builtInOverride(named name: String) -> PresetSettings? {
        loadBuiltInOverrides()[name]
    }

    public func setBuiltInOverride(_ settings: PresetSettings, named name: String) {
        var overrides = loadBuiltInOverrides()
        overrides[name] = settings
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: "builtInPresetOverrides")
        }
    }

    public func clearBuiltInOverride(named name: String) {
        var overrides = loadBuiltInOverrides()
        overrides.removeValue(forKey: name)
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: "builtInPresetOverrides")
        }
    }

    private func loadBuiltInOverrides() -> [String: PresetSettings] {
        guard let data = defaults.data(forKey: "builtInPresetOverrides") else { return [:] }
        return (try? JSONDecoder().decode([String: PresetSettings].self, from: data)) ?? [:]
    }

    // Effective settings for a preset name: user preset, edited built-in,
    // or stock built-in — in that order.
    public func presetSettings(named name: String) -> PresetSettings? {
        if let user = loadPreset(name: name) { return user }
        if let override = builtInOverride(named: name) { return override }
        return PresetSettings.builtIn.first { $0.name == name }?.settings
    }

    // Restore the settings captured before the first preset was applied.
    public func unapplyActivePreset() {
        defer {
            defaults.removeObject(forKey: "presetBaseline")
            defaults.removeObject(forKey: "activePresetName")
        }
        guard let data = defaults.data(forKey: "presetBaseline"),
              let snap = try? JSONDecoder().decode(FormatSettingsSnapshot.self, from: data) else { return }
        restore(snap)
    }

    private func restore(_ snap: FormatSettingsSnapshot) {
        for (key, v) in snap.quality { if let f = OutputFormat(rawValue: key) { setQuality(v, for: f) } }
        for (key, v) in snap.resize { if let f = OutputFormat(rawValue: key) { setResizePercent(v, for: f) } }
        for (key, v) in snap.maxEdge { if let f = OutputFormat(rawValue: key) { setMaxLongestEdge(v, for: f) } }
        for (key, v) in snap.videoPreset { if let f = OutputFormat(rawValue: key) { setVideoPreset(v, for: f) } }
        for (key, v) in snap.stripMetadata { if let f = OutputFormat(rawValue: key) { setStripMetadata(v, for: f) } }
        for (key, v) in snap.audioBitrate { if let f = OutputFormat(rawValue: key) { setAudioBitrate(v, for: f) } }
        for (key, v) in snap.audioSampleRate ?? [:] { if let f = OutputFormat(rawValue: key) { setAudioSampleRate(v, for: f) } }
        for (key, v) in snap.audioChannels ?? [:] { if let f = OutputFormat(rawValue: key) { setAudioChannels(v, for: f) } }
    }

    private func captureSnapshot() -> FormatSettingsSnapshot {
        var snap = FormatSettingsSnapshot()
        for f in OutputFormat.allCases {
            if f.supportsQuality { snap.quality[f.rawValue] = quality(for: f) }
            if f.supportsResize {
                snap.resize[f.rawValue] = resizePercent(for: f)
                snap.maxEdge[f.rawValue] = maxLongestEdge(for: f)
            }
            if f.supportsVideoQuality { snap.videoPreset[f.rawValue] = videoPreset(for: f) }
            if f.category == .image { snap.stripMetadata[f.rawValue] = stripMetadata(for: f) }
            if f.supportsAudioBitrate { snap.audioBitrate[f.rawValue] = audioBitrate(for: f) }
            if f.supportsAudioChannels {
                snap.audioSampleRate = (snap.audioSampleRate ?? [:]).merging([f.rawValue: audioSampleRate(for: f)]) { _, new in new }
                snap.audioChannels = (snap.audioChannels ?? [:]).merging([f.rawValue: audioChannels(for: f)]) { _, new in new }
            }
        }
        return snap
    }

    // Onboarding
    public var showNotifications: Bool {
        get { defaults.object(forKey: "showNotifications") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "showNotifications") }
    }

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

// Per-format settings captured before a preset overwrites them
struct FormatSettingsSnapshot: Codable {
    var quality: [String: Double] = [:]
    var resize: [String: Int] = [:]
    var maxEdge: [String: Int] = [:]
    var videoPreset: [String: String] = [:]
    var stripMetadata: [String: Bool] = [:]
    var audioBitrate: [String: Int] = [:]
    // Optional: baselines saved by earlier versions lack these keys
    var audioSampleRate: [String: Int]?
    var audioChannels: [String: Int]?
}

public struct PresetSettings: Codable, Sendable {
    public var jpegQuality: Double?
    public var heicQuality: Double?
    public var webpQuality: Double?
    public var avifQuality: Double?
    // Below 1.0 reduces PNGs to a colour palette
    public var pngQuality: Double?
    public var resizePercent: Int?
    // Longest edge cap in pixels; nil leaves the per-format setting alone
    public var maxLongestEdge: Int?
    public var videoPreset: String?
    public var stripMetadata: Bool?
    public var audioBitrate: Int?
    // WAV/AIFF/FLAC only
    public var audioSampleRate: Int?
    public var audioChannels: Int?
    public var description: String?

    public init(jpegQuality: Double? = nil, heicQuality: Double? = nil, webpQuality: Double? = nil, avifQuality: Double? = nil,
                pngQuality: Double? = nil, resizePercent: Int? = nil, maxLongestEdge: Int? = nil, videoPreset: String? = nil,
                stripMetadata: Bool? = nil, audioBitrate: Int? = nil, audioSampleRate: Int? = nil, audioChannels: Int? = nil,
                description: String? = nil) {
        self.jpegQuality = jpegQuality
        self.heicQuality = heicQuality
        self.webpQuality = webpQuality
        self.avifQuality = avifQuality
        self.pngQuality = pngQuality
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.resizePercent = resizePercent
        self.maxLongestEdge = maxLongestEdge
        self.videoPreset = videoPreset
        self.stripMetadata = stripMetadata
        self.audioBitrate = audioBitrate
        self.description = description
    }

    public static var builtIn: [(name: String, icon: String, settings: PresetSettings)] {
        builtInGroups.flatMap(\.presets)
    }

    public static let builtInGroups: [(title: String, icon: String, presets: [(name: String, icon: String, settings: PresetSettings)])] = [
        ("Image", "photo", [
        ("Web Optimized", "globe", PresetSettings(
            jpegQuality: 0.75, heicQuality: 0.75, webpQuality: 0.75, avifQuality: 0.7, pngQuality: 0.75,
            resizePercent: 100, maxLongestEdge: 2560, stripMetadata: true,
            description: "Smaller files for websites, longest edge held to 2560 px. Strips metadata."
        )),
        ("Email Friendly", "envelope", PresetSettings(
            jpegQuality: 0.55, heicQuality: 0.55, webpQuality: 0.55, avifQuality: 0.5, pngQuality: 0.55,
            resizePercent: 100, maxLongestEdge: 2048, stripMetadata: true,
            description: "Small files for email attachments. Longest edge held to 2048 px, strips metadata."
        )),
        ("Social Media", "person.2", PresetSettings(
            jpegQuality: 0.8, heicQuality: 0.8, webpQuality: 0.8, pngQuality: 0.8,
            resizePercent: 100, maxLongestEdge: 0, stripMetadata: true,
            description: "Good quality at manageable size. Strips GPS/EXIF data for privacy."
        )),
        ("Maximum Quality", "star", PresetSettings(
            jpegQuality: 1.0, heicQuality: 1.0, webpQuality: 1.0, avifQuality: 1.0, pngQuality: 1.0,
            resizePercent: 100, maxLongestEdge: 0, stripMetadata: false,
            description: "Highest quality, original size, metadata preserved."
        )),
        ("Archive / Lossless", "archivebox", PresetSettings(
            jpegQuality: 1.0, heicQuality: 1.0, webpQuality: 1.0, avifQuality: 1.0, pngQuality: 1.0,
            resizePercent: 100, maxLongestEdge: 0, stripMetadata: false,
            description: "Best for archival. Use with PNG or TIFF for truly lossless output."
        )),
        ("Thumbnail", "photo.on.rectangle", PresetSettings(
            jpegQuality: 0.7, heicQuality: 0.7, webpQuality: 0.7, pngQuality: 0.7,
            resizePercent: 25, stripMetadata: true,
            description: "Tiny previews at 25% size. Great for galleries and catalogs."
        )),
        ("Print Ready", "printer", PresetSettings(
            jpegQuality: 0.95, heicQuality: 0.95, pngQuality: 1.0,
            resizePercent: 100, maxLongestEdge: 0, stripMetadata: false,
            description: "Near-lossless quality at full resolution. Keeps metadata for color profiles."
        )),
        ]),
        ("Video", "film", [
        ("Highest Quality", "film", PresetSettings(
            videoPreset: "highest",
            description: "Visually identical to the original at full resolution. Largest files."
        )),
        ("Balanced", "film.stack", PresetSettings(
            videoPreset: "high",
            description: "Full resolution, barely distinguishable from the original. Typically 2–4x smaller."
        )),
        ("Small File", "arrow.down.circle", PresetSettings(
            videoPreset: "medium",
            description: "Full resolution with slight softening in busy scenes. Good for sharing and uploads."
        )),
        ("Compressed", "archivebox", PresetSettings(
            videoPreset: "low",
            description: "Smallest files at full resolution. Fine detail is visibly reduced."
        )),
        ]),
        ("Audio", "waveform", [
        ("HQ Audio", "headphones", PresetSettings(
            audioBitrate: 256000, audioSampleRate: 44100, audioChannels: 2,
            description: "256 kbps. Near-CD quality for music. WAV/AIFF/FLAC: 44.1 kHz stereo."
        )),
        ("Standard Audio", "speaker.wave.2", PresetSettings(
            audioBitrate: 128000, audioSampleRate: 32000, audioChannels: 2,
            description: "128 kbps. Good balance of quality and size. WAV/AIFF/FLAC: 32 kHz stereo."
        )),
        ("Podcast", "mic", PresetSettings(
            audioBitrate: 64000, audioSampleRate: 22050, audioChannels: 1,
            description: "64 kbps. Optimized for voice recordings. WAV/AIFF/FLAC: 22 kHz mono."
        )),
        ]),
    ]
}

