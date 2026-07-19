import Foundation
import OSLog

public struct GitHubRelease: Codable, Sendable {
    public let tagName: String
    public let name: String?
    public let htmlUrl: String
    public let body: String?
    public let assets: [GitHubAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case body
        case assets
    }
}

public struct GitHubAsset: Codable, Sendable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

public actor UpdateChecker {
    public static let shared = UpdateChecker()

    private let logger = Logger(subsystem: "FinderConvert", category: "update-checker")
    // Change this to your GitHub repo
    private let repoOwner = "turman17"
    private let repoName = "FinderConvert"
    private let currentVersion = "1.0.0"

    public init() {}

    public func checkForUpdate() async -> GitHubRelease? {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                logger.info("Update check: non-200 response")
                return nil
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            // Compare versions
            let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")
            if isNewerVersion(latestVersion, than: currentVersion) {
                logger.info("Update available: \(latestVersion) (current: \(self.currentVersion))")
                return release
            } else {
                logger.info("Up to date: \(self.currentVersion)")
                return nil
            }
        } catch {
            logger.warning("Update check failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newParts = new.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(newParts.count, currentParts.count) {
            let n = i < newParts.count ? newParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if n > c { return true }
            if n < c { return false }
        }
        return false
    }

    public func downloadURL(from release: GitHubRelease) -> URL? {
        // Look for .dmg or .zip asset
        if let asset = release.assets?.first(where: { $0.name.hasSuffix(".dmg") || $0.name.hasSuffix(".zip") }) {
            return URL(string: asset.browserDownloadUrl)
        }
        // Fallback to release page
        return URL(string: release.htmlUrl)
    }
}
