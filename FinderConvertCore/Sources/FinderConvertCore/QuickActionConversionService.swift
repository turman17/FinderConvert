import Foundation
import OSLog

public struct QuickActionConversionService: Sendable {
    private let logger = Logger(subsystem: "FinderConvert", category: "finder-extension")
    private let detector: FileTypeDetector
    private let registry: FinderConvertRegistry

    public init(
        detector: FileTypeDetector = FileTypeDetector(),
        registry: FinderConvertRegistry = FinderConvertRegistry()
    ) {
        self.detector = detector
        self.registry = registry
    }

    public func inspectSelectedURLs(_ urls: [URL]) throws -> [DetectedFile] {
        try urls.map { try detector.detect(url: $0) }
    }

    // Bounded look at a selection for menu building: enumerate at most
    // `limit` files so a huge folder can't stall the caller. Empty result
    // can mean either nothing convertible or no permission to enumerate
    public func sampledOutputs(for urls: [URL], limit: Int = 200) -> [OutputFormat] {
        var files: [DetectedFile] = []
        let fileManager = FileManager.default
        outer: for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let child = enumerator?.nextObject() as? URL {
                    if let detected = try? detector.detect(url: child), detected.detectedType != .unsupported {
                        files.append(detected)
                        if files.count >= limit { break outer }
                    }
                }
            } else if let detected = try? detector.detect(url: url), detected.detectedType != .unsupported {
                files.append(detected)
                if files.count >= limit { break }
            }
        }
        return registry.availableOutputs(for: files)
    }

    public func availableOutputs(for urls: [URL]) throws -> [OutputFormat] {
        let expanded = expandURLs(urls)
        let detected = expanded.compactMap { item -> DetectedFile? in
            guard let df = try? detector.detect(url: item.url), df.detectedType != .unsupported else { return nil }
            return df
        }
        return registry.availableOutputs(for: detected)
    }

    private func expandURLs(_ urls: [URL]) -> [(url: URL, originalRoot: URL?)] {
        var expanded: [(URL, URL?)] = []
        let fileManager = FileManager.default

        for url in urls {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    let resolvedRoot = url.standardizedFileURL.resolvingSymlinksInPath()
                    let enumerator = fileManager.enumerator(at: resolvedRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                    while let childURL = enumerator?.nextObject() as? URL {
                        let resourceValues = try? childURL.resourceValues(forKeys: [.isRegularFileKey])
                        if resourceValues?.isRegularFile == true {
                            let resolvedChild = childURL.standardizedFileURL.resolvingSymlinksInPath()
                            expanded.append((resolvedChild, resolvedRoot))
                        }
                    }
                } else {
                    expanded.append((url, nil))
                }
            }
        }
        return expanded
    }

    public func convert(urls: [URL], requestedOutput: OutputFormat? = nil) async throws -> BatchConversionResult {
        let expanded = expandURLs(urls)
        let detected = expanded.compactMap { item -> (file: DetectedFile, root: URL?)? in
            guard let df = try? detector.detect(url: item.url), df.detectedType != .unsupported else { return nil }
            return (df, item.originalRoot)
        }
        
        let outputs = registry.availableOutputs(for: detected.map { $0.file })
        guard let chosenOutput = requestedOutput ?? outputs.first else {
            throw ConversionError.unsupportedSelection
        }

        var successes: [ConversionResult] = []
        var failures: [ConversionFailure] = []

        for item in detected {
            let file = item.file
            let originalRoot = item.root
            do {
                let bookmarkData = try SecurityScopedAccess(url: file.url).perform {
                    try file.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                }
                
                let policy: DestinationPolicy
                let prefs = PreferencesManager.shared
                if prefs.useCustomOutputFolder, let customFolder = prefs.customOutputFolder {
                    // Custom output folder: mirror structure into chosen folder
                    if let root = originalRoot {
                        policy = .mirroredDirectory(originalRoot: root, newRoot: customFolder.appending(path: root.lastPathComponent, directoryHint: .isDirectory))
                    } else {
                        policy = .mirroredDirectory(originalRoot: file.url.deletingLastPathComponent(), newRoot: customFolder)
                    }
                } else if let root = originalRoot {
                    let newRoot = root.deletingLastPathComponent().appending(path: "\(root.lastPathComponent) converted", directoryHint: .isDirectory)
                    policy = .mirroredDirectory(originalRoot: root, newRoot: newRoot)
                } else {
                    policy = .neverReplace(customSuffix: nil)
                }
                
                let job = ConversionJob(
                    sourceBookmarkData: bookmarkData,
                    requestedOutput: chosenOutput,
                    destinationPolicy: policy
                )
                let engine = registry.engine(for: file.detectedType, output: chosenOutput)
                let result = try await engine.convert(job: job) { _ in }
                successes.append(result)
            } catch let error as ConversionError {
                failures.append(ConversionFailure(sourceURL: file.url, error: error))
            } catch {
                logger.error("Unexpected conversion error: \(error.localizedDescription, privacy: .public)")
                failures.append(ConversionFailure(sourceURL: file.url, error: .filesystemError(error.localizedDescription)))
            }
        }

        return BatchConversionResult(
            requestedOutput: chosenOutput,
            successes: successes,
            failures: failures
        )
    }
}
