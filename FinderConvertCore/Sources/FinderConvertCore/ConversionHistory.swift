import Foundation

public struct ConversionHistoryEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let action: String // "convert", "merge", "split"
    public let inputFiles: [String] // file names
    public let outputFiles: [String] // full paths (or legacy file names)
    public let outputFormat: String
    public let totalInputSize: Int64
    public let totalOutputSize: Int64
    public let success: Bool
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        action: String,
        inputFiles: [String],
        outputFiles: [String],
        outputFormat: String,
        totalInputSize: Int64,
        totalOutputSize: Int64,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.date = date
        self.action = action
        self.inputFiles = inputFiles
        self.outputFiles = outputFiles
        self.outputFormat = outputFormat
        self.totalInputSize = totalInputSize
        self.totalOutputSize = totalOutputSize
        self.success = success
        self.errorMessage = errorMessage
    }
}

public struct ConversionHistoryStore: @unchecked Sendable {
    public static let shared = ConversionHistoryStore()

    private let defaults: UserDefaults
    private let key = "conversionHistory"
    private let maxEntries = 100

    public init(defaults: UserDefaults = UserDefaults(suiteName: "group.com.finderconvert.app.shared") ?? .standard) {
        self.defaults = defaults
    }

    public var entries: [ConversionHistoryEntry] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([ConversionHistoryEntry].self, from: data)) ?? []
        }
        nonmutating set {
            let trimmed = Array(newValue.prefix(maxEntries))
            if let data = try? JSONEncoder().encode(trimmed) {
                defaults.set(data, forKey: key)
            }
        }
    }

    public func add(_ entry: ConversionHistoryEntry) {
        var current = entries
        current.insert(entry, at: 0)
        if current.count > maxEntries { current = Array(current.prefix(maxEntries)) }
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: key)
        }
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
