import Foundation
import OSLog

public enum UpdateInstallError: LocalizedError {
    case noZipAsset
    case downloadFailed
    case extractFailed
    case appNotFoundInArchive
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noZipAsset: "This release has no installable archive."
        case .downloadFailed: "The update could not be downloaded."
        case .extractFailed: "The update archive could not be opened."
        case .appNotFoundInArchive: "The update archive is missing the app."
        case .installFailed(let reason): "The update could not be installed: \(reason)"
        }
    }
}

// Downloads a release's .zip asset, swaps the app bundle in place, and
// returns the URL of the newly installed app so the caller can relaunch.
public actor UpdateInstaller {
    public static let shared = UpdateInstaller()

    private let logger = Logger(subsystem: "FinderConvert", category: "update-installer")

    public init() {}

    public func installUpdate(from release: GitHubRelease, into targetAppURL: URL) async throws -> URL {
        guard let zipAsset = release.assets?.first(where: { $0.name.hasSuffix(".zip") }),
              let zipURL = URL(string: zipAsset.browserDownloadUrl) else {
            throw UpdateInstallError.noZipAsset
        }

        logger.info("Downloading update from \(zipURL.absoluteString, privacy: .public)")
        let (downloadedURL, response) = try await URLSession.shared.download(from: zipURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateInstallError.downloadFailed
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderConvertUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // Extract with ditto (preserves signatures and permissions)
        let extractDir = workDir.appendingPathComponent("extracted")
        try runProcess("/usr/bin/ditto", ["-x", "-k", downloadedURL.path, extractDir.path],
                       orThrow: UpdateInstallError.extractFailed)

        guard let newAppURL = findAppBundle(in: extractDir) else {
            throw UpdateInstallError.appNotFoundInArchive
        }

        // Downloads from URLSession normally carry no quarantine, but strip
        // defensively so Gatekeeper never blocks the swapped-in bundle
        try? runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newAppURL.path],
                        orThrow: UpdateInstallError.extractFailed)

        // Swap: move the running bundle aside, move the new one in, roll
        // back if that fails
        let backupURL = workDir.appendingPathComponent("previous.app")
        do {
            try FileManager.default.moveItem(at: targetAppURL, to: backupURL)
        } catch {
            throw UpdateInstallError.installFailed("cannot move current app (\(error.localizedDescription))")
        }
        do {
            try FileManager.default.moveItem(at: newAppURL, to: targetAppURL)
        } catch {
            try? FileManager.default.moveItem(at: backupURL, to: targetAppURL)
            throw UpdateInstallError.installFailed("cannot place new app (\(error.localizedDescription))")
        }

        logger.info("Update installed at \(targetAppURL.path, privacy: .public)")
        return targetAppURL
    }

    private func findAppBundle(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        if let app = contents.first(where: { $0.pathExtension == "app" }) { return app }
        // One level deep (zip may contain a wrapping folder)
        for sub in contents where sub.hasDirectoryPath {
            if let app = findAppBundle(in: sub) { return app }
        }
        return nil
    }

    private func runProcess(_ launchPath: String, _ arguments: [String], orThrow error: UpdateInstallError) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw error }
    }
}
