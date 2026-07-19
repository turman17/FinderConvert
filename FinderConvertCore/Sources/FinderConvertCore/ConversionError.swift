import Foundation

public enum ConversionError: LocalizedError, Sendable, Equatable {
    case unsupportedSelection
    case unsupportedFileType(String)
    case unsupportedOutput(OutputFormat)
    case unreadableInput
    case failedToDecodeImage
    case failedToEncodeImage(OutputFormat)
    case invalidDestination
    case notificationAuthorizationMissing
    case filesystemError(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            localized("unsupported_selection")
        case let .unsupportedFileType(name):
            localized("unsupported_file_type", name)
        case let .unsupportedOutput(format):
            localized("unsupported_output", format.displayName)
        case .unreadableInput:
            localized("unreadable_input")
        case .failedToDecodeImage:
            localized("failed_to_decode_image")
        case let .failedToEncodeImage(format):
            localized("failed_to_encode_image", format.displayName)
        case .invalidDestination:
            localized("invalid_destination")
        case let .filesystemError(message):
            message
        case .notificationAuthorizationMissing:
            localized("notification_authorization_missing")
        }
    }

    private func localized(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: .module, comment: "")
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
