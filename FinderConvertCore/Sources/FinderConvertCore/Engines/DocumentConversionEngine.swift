import AppKit
import Foundation
import OSLog
import PDFKit
import UniformTypeIdentifiers
import WebKit

public actor DocumentConversionEngine: ConversionEngine {
    public let identifier = "com.finderconvert.engine.document.text"
    private let logger = Logger(subsystem: "FinderConvert", category: "document-engine")
    private let naming = OutputNamingStrategy()

    public init() {}

    private static let textInputs: Set<DetectedFileType> = [.rtf, .html, .txt, .markdown, .docx]
    private static let textOutputs: Set<OutputFormat> = [.pdf, .rtf, .html, .txt]

    public nonisolated func supports(input: DetectedFileType, output: OutputFormat) -> Bool {
        Self.textInputs.contains(input) && Self.textOutputs.contains(output)
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
            .appendingPathExtension(job.requestedOutput.preferredExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Read source document into NSAttributedString
        let attributedString = try readDocument(at: sourceURL, type: inputType)
        progress(0.4)

        // Write to target format
        switch job.requestedOutput {
        case .pdf:
            try await writePDF(from: attributedString, sourceType: inputType, sourceURL: sourceURL, to: tempURL)
        case .rtf:
            try writeRTF(from: attributedString, to: tempURL)
        case .html:
            // For markdown → html, produce clean HTML directly
            if inputType == .markdown {
                let mdData = try Data(contentsOf: sourceURL)
                let mdString = String(data: mdData, encoding: .utf8) ?? ""
                try markdownToHTML(mdString).write(to: tempURL, atomically: true, encoding: .utf8)
            } else {
                try writeHTML(from: attributedString, to: tempURL)
            }
        case .txt:
            try writePlainText(from: attributedString, to: tempURL)
        default:
            throw ConversionError.unsupportedOutput(job.requestedOutput)
        }

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

        // Convert Markdown to HTML before parsing
        var effectiveType = type
        if type == .markdown {
            let markdown = String(data: data, encoding: .utf8) ?? ""
            let html = markdownToHTML(markdown)
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

    // MARK: - Writing

    private func writePDF(from text: NSAttributedString, sourceType: DetectedFileType, sourceURL: URL, to url: URL) async throws {
        // For HTML and Markdown, use WebKit for better rendering
        if sourceType == .html || sourceType == .markdown {
            try await renderHTMLToPDF(sourceURL: sourceURL, to: url, isMarkdown: sourceType == .markdown)
            return
        }

        // Copy string data to cross actor boundary safely
        let plainString = text.string
        let rtfData = try? text.data(from: NSRange(location: 0, length: text.length),
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])

        try await MainActor.run {
            let pageWidth: CGFloat = 612
            let pageHeight: CGFloat = 792
            let margin: CGFloat = 72
            let contentWidth = pageWidth - margin * 2
            let contentHeight = pageHeight - margin * 2

            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))

            if let rtfData,
               let restored = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                textView.textStorage?.setAttributedString(restored)
            } else {
                textView.string = plainString
            }
            textView.sizeToFit()

            let pdfData = textView.dataWithPDF(inside: textView.bounds)
            try pdfData.write(to: url)
        }
    }

    @MainActor
    private func renderHTMLToPDF(sourceURL: URL, to outputURL: URL, isMarkdown: Bool = false) async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        let htmlData = try Data(contentsOf: sourceURL)
        guard let rawString = String(data: htmlData, encoding: .utf8) else {
            throw ConversionError.unreadableInput
        }

        let htmlString: String
        if isMarkdown {
            htmlString = markdownToHTML(rawString)
        } else {
            htmlString = rawString
        }

        webView.loadHTMLString(htmlString, baseURL: sourceURL.deletingLastPathComponent())

        // Wait for load
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            class LoadDelegate: NSObject, WKNavigationDelegate {
                let continuation: CheckedContinuation<Void, Error>
                init(_ c: CheckedContinuation<Void, Error>) { self.continuation = c }
                func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                    continuation.resume()
                }
                func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
                    continuation.resume(throwing: error)
                }
            }
            let delegate = LoadDelegate(continuation)
            objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            webView.navigationDelegate = delegate
        }

        let pdfConfig = WKPDFConfiguration()
        pdfConfig.rect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdfData = try await webView.pdf(configuration: pdfConfig)
        try pdfData.write(to: outputURL)
    }

    private func writeRTF(from text: NSAttributedString, to url: URL) throws {
        let range = NSRange(location: 0, length: text.length)
        let data = try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try data.write(to: url)
    }

    private func writeHTML(from text: NSAttributedString, to url: URL) throws {
        let range = NSRange(location: 0, length: text.length)
        let data = try text.data(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ])
        try data.write(to: url)
    }

    private func writePlainText(from text: NSAttributedString, to url: URL) throws {
        try text.string.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Markdown

    nonisolated private func markdownToHTML(_ markdown: String) -> String {
        var html = ""
        let lines = markdown.components(separatedBy: .newlines)
        var inCodeBlock = false
        var inList = false
        var listType = "" // "ul" or "ol"

        for line in lines {
            // Code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    html += "</code></pre>\n"
                    inCodeBlock = false
                } else {
                    if inList { html += "</\(listType)>\n"; inList = false }
                    html += "<pre><code>"
                    inCodeBlock = true
                }
                continue
            }
            if inCodeBlock {
                html += escapeHTML(line) + "\n"
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line
            if trimmed.isEmpty {
                if inList { html += "</\(listType)>\n"; inList = false }
                continue
            }

            // Headers
            if trimmed.hasPrefix("######") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h6>\(processInline(String(trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces))))</h6>\n"
            } else if trimmed.hasPrefix("#####") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h5>\(processInline(String(trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces))))</h5>\n"
            } else if trimmed.hasPrefix("####") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h4>\(processInline(String(trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces))))</h4>\n"
            } else if trimmed.hasPrefix("###") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h3>\(processInline(String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))))</h3>\n"
            } else if trimmed.hasPrefix("##") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h2>\(processInline(String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))))</h2>\n"
            } else if trimmed.hasPrefix("# ") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h1>\(processInline(String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))))</h1>\n"
            }
            // Horizontal rule
            else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<hr/>\n"
            }
            // Unordered list
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList || listType != "ul" {
                    if inList { html += "</\(listType)>\n" }
                    html += "<ul>\n"; inList = true; listType = "ul"
                }
                html += "<li>\(processInline(String(trimmed.dropFirst(2))))</li>\n"
            }
            // Ordered list
            else if trimmed.first?.isNumber == true && trimmed.contains(". ") {
                if let dotIdx = trimmed.firstIndex(of: "."), trimmed[trimmed.startIndex..<dotIdx].allSatisfy(\.isNumber) {
                    if !inList || listType != "ol" {
                        if inList { html += "</\(listType)>\n" }
                        html += "<ol>\n"; inList = true; listType = "ol"
                    }
                    let content = String(trimmed[trimmed.index(after: dotIdx)...]).trimmingCharacters(in: .whitespaces)
                    html += "<li>\(processInline(content))</li>\n"
                } else {
                    if inList { html += "</\(listType)>\n"; inList = false }
                    html += "<p>\(processInline(trimmed))</p>\n"
                }
            }
            // Blockquote
            else if trimmed.hasPrefix("> ") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<blockquote><p>\(processInline(String(trimmed.dropFirst(2))))</p></blockquote>\n"
            }
            // Regular paragraph
            else {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<p>\(processInline(trimmed))</p>\n"
            }
        }

        if inCodeBlock { html += "</code></pre>\n" }
        if inList { html += "</\(listType)>\n" }

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
        body { font-family: -apple-system, sans-serif; max-width: 700px; margin: 40px auto; padding: 0 20px; line-height: 1.6; color: #333; }
        code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
        pre code { display: block; padding: 16px; overflow-x: auto; }
        blockquote { border-left: 4px solid #ddd; margin: 0; padding-left: 16px; color: #666; }
        h1, h2, h3 { margin-top: 1.5em; }
        hr { border: none; border-top: 1px solid #ddd; margin: 2em 0; }
        </style></head><body>
        \(html)
        </body></html>
        """
    }

    nonisolated private func processInline(_ text: String) -> String {
        var result = escapeHTML(text)
        // Bold: **text** or __text__
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: "__(.+?)__", with: "<strong>$1</strong>", options: .regularExpression)
        // Italic: *text* or _text_
        result = result.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?<![a-zA-Z])_(.+?)_(?![a-zA-Z])", with: "<em>$1</em>", options: .regularExpression)
        // Inline code: `text`
        result = result.replacingOccurrences(of: "`(.+?)`", with: "<code>$1</code>", options: .regularExpression)
        // Links: [text](url)
        result = result.replacingOccurrences(of: "\\[(.+?)\\]\\((.+?)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return result
    }

    nonisolated private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
