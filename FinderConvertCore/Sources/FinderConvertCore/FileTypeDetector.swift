import Foundation
import UniformTypeIdentifiers

public struct FileTypeDetector: Sendable {
    public init() {}

    public func detect(url: URL) throws -> DetectedFile {
        let resourceValues = try url.resourceValues(forKeys: [
            .contentTypeKey,
            .fileSizeKey,
            .isRegularFileKey,
            .nameKey,
        ])

        guard resourceValues.isRegularFile == true else {
            throw ConversionError.unreadableInput
        }

        let fallbackType = fallbackDetectedType(for: url.pathExtension)
        let contentType = resourceValues.contentType
        let detectedType = detectType(contentType: contentType, fileExtension: url.pathExtension, fallback: fallbackType)

        return DetectedFile(
            url: url,
            contentType: contentType,
            category: detectedType.category,
            fileExtension: url.pathExtension.lowercased(),
            fileSize: resourceValues.fileSize.map(Int64.init),
            detectedType: detectedType
        )
    }

    public func detectType(
        contentType: UTType?,
        fileExtension: String,
        fallback: DetectedFileType? = nil
    ) -> DetectedFileType {
        if let contentType {
            if contentType.conforms(to: .jpeg) {
                return .jpeg
            }
            if contentType.conforms(to: .png) {
                return .png
            }
            if contentType.conforms(to: UTType("public.heic") ?? .image) {
                return .heic
            }
            if contentType.conforms(to: .tiff) {
                return .tiff
            }
            if contentType.conforms(to: .pdf) {
                return .pdf
            }
            if contentType.conforms(to: .mpeg4Movie) {
                return .mp4
            }
            if contentType.conforms(to: .quickTimeMovie) {
                return .mov
            }
            if contentType.conforms(to: .gif) {
                return .gif
            }
            if contentType.conforms(to: UTType("org.webmproject.webp") ?? .image) {
                return .webp
            }
            if contentType.conforms(to: .bmp) {
                return .bmp
            }
            if contentType.conforms(to: .svg) {
                return .svg
            }
            if contentType.conforms(to: UTType("public.avif") ?? .image) {
                return .avif
            }
            if contentType.conforms(to: UTType("org.webmproject.webm") ?? .movie) {
                return .webm
            }
            // Audio types
            if contentType.conforms(to: .mp3) {
                return .mp3
            }
            if contentType.conforms(to: UTType("public.mpeg-4-audio") ?? .audio) {
                return .m4a
            }
            if contentType.conforms(to: .wav) {
                return .wav
            }
            if contentType.conforms(to: .aiff) {
                return .aiff
            }
            if contentType.conforms(to: UTType("org.xiph.flac") ?? .audio) {
                return .flac
            }
            if contentType.conforms(to: UTType("org.xiph.ogg") ?? .audio) {
                return .ogg
            }
            // Spreadsheet types (check before plainText since CSV conforms to plainText)
            if contentType.conforms(to: .commaSeparatedText) {
                return .csv
            }
            if contentType.conforms(to: .tabSeparatedText) {
                return .tsv
            }
            if contentType.conforms(to: UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data) {
                return .xlsx
            }
            // Document types
            if contentType.conforms(to: .rtf) {
                return .rtf
            }
            if contentType.conforms(to: .html) {
                return .html
            }
            if contentType.conforms(to: UTType("org.openxmlformats.wordprocessingml.document") ?? .data) {
                return .docx
            }
            if contentType.conforms(to: UTType("org.idpf.epub-container") ?? .data) {
                return .epub
            }
            if contentType.conforms(to: .json) {
                return .json
            }
            if contentType.conforms(to: .plainText) {
                // Check extension for markdown before falling back to txt
                let ext = fileExtension.lowercased()
                if ext == "md" || ext == "markdown" {
                    return .markdown
                }
                return .txt
            }
        }

        if let fallback {
            return fallback
        }

        return fallbackDetectedType(for: fileExtension)
    }

    public func fallbackDetectedType(for fileExtension: String) -> DetectedFileType {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "heic": return .heic
        case "tiff", "tif": return .tiff
        case "gif": return .gif
        case "webp": return .webp
        case "bmp": return .bmp
        case "svg": return .svg
        case "avif": return .avif
        case "epub": return .epub
        case "pdf": return .pdf
        case "mp4", "m4v": return .mp4
        case "mov": return .mov
        case "webm": return .webm
        case "mp3": return .mp3
        case "m4a", "aac": return .m4a
        case "wav", "wave": return .wav
        case "aiff", "aif": return .aiff
        case "flac": return .flac
        case "ogg", "oga": return .ogg
        case "rtf": return .rtf
        case "html", "htm": return .html
        case "csv": return .csv
        case "tsv": return .tsv
        case "xlsx", "xls": return .xlsx
        case "md", "markdown": return .markdown
        case "json": return .json
        case "txt", "text", "log": return .txt
        case "docx": return .docx
        case "doc": return .docx
        default: return .unsupported
        }
    }
}
