import Foundation

public struct OutputNamingStrategy: Sendable {
    private static let maxCollisionAttempts = 10_000

    public init() {}

    public func destinationURL(
        for sourceURL: URL,
        outputFormat: OutputFormat,
        policy: DestinationPolicy = .neverReplace(customSuffix: nil),
        fileManager: FileManager = .default
    ) throws -> URL {
        let parentDirectory = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        
        let ext = outputFormat.preferredExtension
        var candidate: URL
        var parentDir: URL
        var baseNameNoSuffix: String
        var activeSuffix: String = ""
        
        switch policy {
        case let .neverReplace(customSuffix):
            let defaultSuffix = PreferencesManager.shared.renameSuffix
            activeSuffix = customSuffix?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? customSuffix! : defaultSuffix
            parentDir = parentDirectory
            baseNameNoSuffix = baseName
            candidate = parentDir.appending(path: "\(baseNameNoSuffix)\(activeSuffix).\(ext)", directoryHint: .notDirectory)
            
        case let .mirroredDirectory(originalRoot, newRoot):
            let resolvedSource = sourceURL.standardizedFileURL.resolvingSymlinksInPath().path
            let resolvedRoot = originalRoot.standardizedFileURL.resolvingSymlinksInPath().path
            let relativePath = resolvedSource.replacingOccurrences(of: resolvedRoot, with: "")
            let cleanRelative = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            candidate = newRoot.appending(path: cleanRelative, directoryHint: .notDirectory)
            candidate.deletePathExtension()
            candidate.appendPathExtension(ext)
            
            parentDir = candidate.deletingLastPathComponent()
            baseNameNoSuffix = candidate.deletingPathExtension().lastPathComponent
            
            // Ensure parent directories exist
            if !fileManager.fileExists(atPath: parentDir.path) {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            }
        }

        if !fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }

        for index in 2...Self.maxCollisionAttempts {
            candidate = parentDir.appending(path: "\(baseNameNoSuffix)\(activeSuffix) \(index).\(ext)", directoryHint: .notDirectory)
            if !fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }

        throw ConversionError.invalidDestination
    }
}
