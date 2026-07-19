import Foundation
import UniformTypeIdentifiers

public enum FileCategory: String, Codable, Sendable {
    case image
    case video
    case audio
    case document
    case unsupported
}

public enum OutputFormat: String, Codable, CaseIterable, Sendable {
    // Image
    case jpeg
    case png
    case heic
    case tiff
    case gif
    case bmp
    case ico
    case avif
    case webp
    // Video
    case mp4
    case mov
    case hevc
    // Audio
    case mp3
    case m4a
    case wav
    case aiff
    case flac
    // Document
    case pdf
    case rtf
    case html
    case txt
    // Spreadsheet
    case csv
    case tsv
    case xlsx
    case docx

    public var preferredExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .tiff: "tiff"
        case .gif: "gif"
        case .bmp: "bmp"
        case .ico: "ico"
        case .avif: "avif"
        case .webp: "webp"
        case .mp4: "mp4"
        case .mov: "mov"
        case .hevc: "mov"
        case .mp3: "mp3"
        case .m4a: "m4a"
        case .wav: "wav"
        case .aiff: "aiff"
        case .flac: "flac"
        case .pdf: "pdf"
        case .rtf: "rtf"
        case .html: "html"
        case .txt: "txt"
        case .csv: "csv"
        case .tsv: "tsv"
        case .xlsx: "xlsx"
        case .docx: "docx"
        }
    }

    public var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .gif: "GIF"
        case .bmp: "BMP"
        case .ico: "ICO"
        case .avif: "AVIF"
        case .webp: "WebP"
        case .mp4: "MP4"
        case .mov: "MOV"
        case .hevc: "HEVC"
        case .mp3: "MP3"
        case .m4a: "M4A (AAC)"
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .flac: "FLAC"
        case .pdf: "PDF"
        case .rtf: "RTF"
        case .html: "HTML"
        case .txt: "Plain Text"
        case .csv: "CSV"
        case .tsv: "TSV"
        case .xlsx: "Excel"
        case .docx: "Word"
        }
    }

    public var category: FileCategory {
        switch self {
        case .jpeg, .png, .heic, .tiff, .gif, .bmp, .ico, .avif, .webp:
            return .image
        case .mp4, .mov, .hevc:
            return .video
        case .mp3, .m4a, .wav, .aiff, .flac:
            return .audio
        case .pdf, .rtf, .html, .txt, .csv, .tsv, .xlsx, .docx:
            return .document
        }
    }

    public var supportsQuality: Bool {
        switch self {
        case .jpeg, .heic, .avif, .webp: return true
        default: return false
        }
    }

    public var supportsResize: Bool {
        category == .image
    }

    public var supportsVideoQuality: Bool {
        switch self {
        case .mp4, .mov, .hevc: return true
        default: return false
        }
    }

    public var supportsAudioBitrate: Bool {
        switch self {
        case .mp3, .m4a: return true
        default: return false
        }
    }

    public var supportsAudioSampleRate: Bool {
        switch self {
        case .mp3, .m4a, .wav, .aiff, .flac: return true
        default: return false
        }
    }

    public var defaultQuality: Double {
        switch self {
        case .jpeg, .heic, .avif, .webp: return 0.9
        default: return 1.0
        }
    }
}

public enum ConversionState: Codable, Sendable, Equatable {
    case queued
    case preparing
    case converting(progress: Double)
    case finalizing
    case completed
    case failed(message: String)
    case cancelled
}

public struct ConversionJob: Codable, Sendable, Identifiable {
    public let id: UUID
    public let sourceBookmarkData: Data
    public let requestedOutput: OutputFormat
    public let destinationPolicy: DestinationPolicy
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceBookmarkData: Data,
        requestedOutput: OutputFormat,
        destinationPolicy: DestinationPolicy,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceBookmarkData = sourceBookmarkData
        self.requestedOutput = requestedOutput
        self.destinationPolicy = destinationPolicy
        self.createdAt = createdAt
    }
}

public enum DestinationPolicy: Codable, Sendable, Equatable {
    case neverReplace(customSuffix: String?)
    case mirroredDirectory(originalRoot: URL, newRoot: URL)
}

public struct DetectedFile: Sendable, Hashable {
    public let url: URL
    public let contentType: UTType?
    public let category: FileCategory
    public let fileExtension: String
    public let fileSize: Int64?
    public let detectedType: DetectedFileType

    public init(
        url: URL,
        contentType: UTType?,
        category: FileCategory,
        fileExtension: String,
        fileSize: Int64?,
        detectedType: DetectedFileType
    ) {
        self.url = url
        self.contentType = contentType
        self.category = category
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.detectedType = detectedType
    }
}

public enum DetectedFileType: String, Codable, Sendable, Hashable {
    // Image
    case jpeg
    case png
    case heic
    case tiff
    case gif
    case webp
    case bmp
    case svg
    case avif
    // Video
    case mp4
    case mov
    case webm
    // Audio
    case mp3
    case m4a
    case wav
    case aiff
    case flac
    case ogg
    // Document
    case pdf
    case rtf
    case html
    case txt
    case markdown
    case docx
    case json
    case epub
    // Spreadsheet
    case csv
    case tsv
    case xlsx
    case unsupported

    public var category: FileCategory {
        switch self {
        case .jpeg, .png, .heic, .tiff, .gif, .webp, .bmp, .svg, .avif:
            return .image
        case .mp4, .mov, .webm:
            return .video
        case .mp3, .m4a, .wav, .aiff, .flac, .ogg:
            return .audio
        case .pdf, .rtf, .html, .txt, .markdown, .docx, .json, .epub, .csv, .tsv, .xlsx:
            return .document
        case .unsupported:
            return .unsupported
        }
    }

    public var suggestedOutput: OutputFormat? {
        switch self {
        case .jpeg: return .png
        case .png: return .jpeg
        case .heic: return .jpeg
        case .tiff: return .png
        case .gif: return .png
        case .webp: return .png
        case .bmp: return .png
        case .svg: return .png
        case .avif: return .png
        case .pdf: return .jpeg
        case .rtf: return .pdf
        case .html: return .pdf
        case .txt: return .pdf
        case .markdown: return .html
        case .docx: return .pdf
        case .json: return .csv
        case .epub: return .pdf
        case .csv: return .xlsx
        case .tsv: return .xlsx
        case .xlsx: return .csv
        case .mp4: return .mov
        case .mov: return .mp4
        case .webm: return .mp4
        case .mp3: return .m4a
        case .m4a: return .wav
        case .wav: return .m4a
        case .aiff: return .m4a
        case .flac: return .m4a
        case .ogg: return .m4a
        case .unsupported: return nil
        }
    }
}

public struct ConversionResult: Sendable, Equatable {
    public let sourceURL: URL
    public let outputURL: URL
    public let outputFormat: OutputFormat

    public init(sourceURL: URL, outputURL: URL, outputFormat: OutputFormat) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.outputFormat = outputFormat
    }
}

public struct BatchConversionResult: Sendable, Equatable {
    public let requestedOutput: OutputFormat
    public let successes: [ConversionResult]
    public let failures: [ConversionFailure]

    public init(requestedOutput: OutputFormat, successes: [ConversionResult], failures: [ConversionFailure]) {
        self.requestedOutput = requestedOutput
        self.successes = successes
        self.failures = failures
    }
}

public struct ConversionFailure: Sendable, Equatable {
    public let sourceURL: URL
    public let error: ConversionError

    public init(sourceURL: URL, error: ConversionError) {
        self.sourceURL = sourceURL
        self.error = error
    }
}
