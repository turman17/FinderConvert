import AppKit
import Foundation
import OSLog

public actor DocxWriterEngine: ConversionEngine {
    public let identifier = "com.finderconvert.engine.docx.writer"
    private let logger = Logger(subsystem: "FinderConvert", category: "docx-writer-engine")
    private let naming = OutputNamingStrategy()

    public init() {}

    private static let supportedInputs: Set<DetectedFileType> = [.txt, .rtf, .html, .markdown, .docx]
    private static let supportedOutputs: Set<OutputFormat> = [.docx]

    public nonisolated func supports(input: DetectedFileType, output: OutputFormat) -> Bool {
        Self.supportedInputs.contains(input) && Self.supportedOutputs.contains(output)
    }

    public func convert(
        job: ConversionJob,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ConversionResult {
        var isStale = false
        let sourceURL = try URL(
            resolvingBookmarkData: job.sourceBookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        let access = SecurityScopedAccess(url: sourceURL)
        let inputType = try FileTypeDetector().detect(url: sourceURL).detectedType
        guard supports(input: inputType, output: job.requestedOutput) else {
            throw ConversionError.unsupportedOutput(job.requestedOutput)
        }

        progress(0.1)

        let destinationURL = try naming.destinationURL(
            for: sourceURL,
            outputFormat: job.requestedOutput,
            policy: job.destinationPolicy
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("docx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Read source into NSAttributedString
        let attributedString = try readDocument(at: sourceURL, type: inputType)
        progress(0.4)

        // Build DOCX ZIP structure
        try writeDOCX(from: attributedString, to: tempURL)
        progress(0.9)

        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        _ = access
        progress(1.0)
        return ConversionResult(sourceURL: sourceURL, outputURL: destinationURL, outputFormat: job.requestedOutput)
    }

    public func cancel(jobID: UUID) async {}

    // MARK: - Reading

    private func readDocument(at url: URL, type: DetectedFileType) throws -> NSAttributedString {
        var data = try Data(contentsOf: url)

        var effectiveType = type
        if type == .markdown {
            let markdown = String(data: data, encoding: .utf8) ?? ""
            let html = wrapPlainHTML(markdown)
            data = html.data(using: .utf8) ?? data
            effectiveType = .html
        }

        let documentType: NSAttributedString.DocumentType
        switch effectiveType {
        case .rtf: documentType = .rtf
        case .html: documentType = .html
        case .docx: documentType = .docFormat
        case .txt: documentType = .plain
        default: documentType = .plain
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: documentType,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]

        return try NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    private func wrapPlainHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let paragraphs = escaped.components(separatedBy: "\n")
            .map { "<p>\($0)</p>" }
            .joined(separator: "\n")
        return "<html><body>\(paragraphs)</body></html>"
    }

    // MARK: - DOCX Writing

    private func writeDOCX(from text: NSAttributedString, to url: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wordDir = tempDir.appendingPathComponent("word")
        let relsRoot = tempDir.appendingPathComponent("_rels")
        let relsWord = wordDir.appendingPathComponent("_rels")

        for dir in [wordDir, relsRoot, relsWord] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // [Content_Types].xml
        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        // _rels/.rels
        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """.write(to: relsRoot.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        // word/_rels/document.xml.rels
        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        </Relationships>
        """.write(to: relsWord.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)

        // word/document.xml
        let documentXML = buildDocumentXML(from: text)
        try documentXML.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        // ZIP into .docx using ditto (same pattern as SpreadsheetConversionEngine)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", tempDir.path, url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ConversionError.filesystemError("Failed to create DOCX archive.")
        }
    }

    private func buildDocumentXML(from text: NSAttributedString) -> String {
        var paragraphs = ""
        let fullRange = NSRange(location: 0, length: text.length)
        let plainText = text.string

        // Split into paragraphs and preserve runs with formatting
        let lines = plainText.components(separatedBy: "\n")
        var charIndex = 0

        for line in lines {
            let lineLength = line.utf16.count
            if lineLength == 0 {
                paragraphs += "    <w:p/>\n"
            } else {
                paragraphs += "    <w:p>\n"

                // Enumerate attribute runs within this line
                let lineRange = NSRange(location: charIndex, length: lineLength)
                text.enumerateAttributes(in: lineRange, options: []) { attrs, range, _ in
                    let runStart = range.location - charIndex
                    let runEnd = runStart + range.length
                    let startIdx = plainText.utf16.index(plainText.utf16.startIndex, offsetBy: range.location)
                    let endIdx = plainText.utf16.index(startIdx, offsetBy: range.length)
                    let runText = String(plainText[startIdx..<endIdx])

                    let escaped = xmlEscape(runText)
                    var rPr = ""

                    // Bold
                    if let font = attrs[.font] as? NSFont {
                        let traits = NSFontManager.shared.traits(of: font)
                        if traits.contains(.boldFontMask) {
                            rPr += "<w:b/>"
                        }
                        if traits.contains(.italicFontMask) {
                            rPr += "<w:i/>"
                        }
                        // Font size in half-points
                        let sizeInHalfPts = Int(font.pointSize * 2)
                        rPr += "<w:sz w:val=\"\(sizeInHalfPts)\"/>"
                    }

                    paragraphs += "      <w:r>"
                    if !rPr.isEmpty {
                        paragraphs += "<w:rPr>\(rPr)</w:rPr>"
                    }
                    paragraphs += "<w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>\n"
                }

                paragraphs += "    </w:p>\n"
            }
            charIndex += lineLength + 1 // +1 for the newline
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
                    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
                    xmlns:o="urn:schemas-microsoft-com:office:office"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
                    xmlns:v="urn:schemas-microsoft-com:vml"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:w10="urn:schemas-microsoft-com:office:word"
                    xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml"
                    mc:Ignorable="w14 wp14">
          <w:body>
        \(paragraphs)  </w:body>
        </w:document>
        """
    }

    private func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
