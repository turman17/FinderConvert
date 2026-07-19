import Foundation
import OSLog

private let logger = Logger(subsystem: "FinderConvert", category: "security-scoped-access")

public final class SecurityScopedAccess: Sendable {
    private let url: URL
    private let didStart: Bool

    public init(url: URL) {
        self.url = url
        self.didStart = url.startAccessingSecurityScopedResource()
        logger.info("FinderConvert SecurityScopedAccess: startAccessingSecurityScopedResource for \(url.path(percentEncoded: false), privacy: .public) returned \(self.didStart, privacy: .public)")
    }

    deinit {
        if didStart {
            url.stopAccessingSecurityScopedResource()
            logger.info("FinderConvert SecurityScopedAccess: stopAccessingSecurityScopedResource for \(self.url.path(percentEncoded: false), privacy: .public)")
        }
    }

    public func perform<T>(_ action: () throws -> T) throws -> T {
        return try action()
    }

    public func performAsync<T>(_ action: @Sendable () async throws -> T) async throws -> T {
        return try await action()
    }
}
