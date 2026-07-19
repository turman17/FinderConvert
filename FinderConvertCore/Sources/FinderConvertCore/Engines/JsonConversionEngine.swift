import Foundation
import OSLog

public actor JsonConversionEngine: ConversionEngine {
    public let identifier = "com.finderconvert.engine.json"
    private let logger = Logger(subsystem: "FinderConvert", category: "json-engine")
    private let naming = OutputNamingStrategy()

    public init() {}

    public nonisolated func supports(input: DetectedFileType, output: OutputFormat) -> Bool {
        switch (input, output) {
        case (.json, .csv), (.json, .tsv), (.json, .xlsx):
            return true
        case (.csv, .xlsx), (.tsv, .xlsx):
            // Already handled by SpreadsheetConversionEngine
            return false
        default:
            return false
        }
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
        progress(0.1)

        let data = try Data(contentsOf: sourceURL)
        let rows = try jsonToRows(data)
        progress(0.5)

        let destinationURL = try naming.destinationURL(
            for: sourceURL,
            outputFormat: job.requestedOutput,
            policy: job.destinationPolicy
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(job.requestedOutput.preferredExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        switch job.requestedOutput {
        case .csv:
            try writeDelimited(rows: rows, delimiter: ",", to: tempURL)
        case .tsv:
            try writeDelimited(rows: rows, delimiter: "\t", to: tempURL)
        case .xlsx:
            // Write as CSV to temp, then use spreadsheet engine pattern
            try writeDelimited(rows: rows, delimiter: ",", to: tempURL)
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

    nonisolated private func jsonToRows(_ data: Data) throws -> [[String]] {
        let json = try JSONSerialization.jsonObject(with: data)

        // If it's an array of objects, flatten to table
        if let array = json as? [[String: Any]] {
            return flattenObjectArray(array)
        }

        // If it's a single object, treat as one-row table
        if let object = json as? [String: Any] {
            return flattenObjectArray([object])
        }

        // If it's an array of arrays, use directly
        if let array = json as? [[Any]] {
            return array.map { row in row.map { stringify($0) } }
        }

        // If it's a simple array, one column
        if let array = json as? [Any] {
            return [["value"]] + array.map { [stringify($0)] }
        }

        throw ConversionError.filesystemError("JSON structure is not convertible to tabular format.")
    }

    nonisolated private func flattenObjectArray(_ objects: [[String: Any]]) -> [[String]] {
        // Collect all keys in order of first appearance
        var keyOrder: [String] = []
        var keySet = Set<String>()
        for obj in objects {
            for key in obj.keys.sorted() {
                if keySet.insert(key).inserted {
                    keyOrder.append(key)
                }
            }
        }

        // Header row
        var rows: [[String]] = [keyOrder]

        // Data rows
        for obj in objects {
            let row = keyOrder.map { key -> String in
                guard let value = obj[key] else { return "" }
                return stringify(value)
            }
            rows.append(row)
        }

        return rows
    }

    nonisolated private func stringify(_ value: Any) -> String {
        switch value {
        case is NSNull:
            return ""
        case let str as String:
            return str
        case let num as NSNumber:
            // Check if it's a boolean
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            return num.stringValue
        case let arr as [Any]:
            // Nested arrays become JSON strings
            if let data = try? JSONSerialization.data(withJSONObject: arr),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return ""
        case let dict as [String: Any]:
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return ""
        default:
            return "\(value)"
        }
    }

    nonisolated private func writeDelimited(rows: [[String]], delimiter: String, to url: URL) throws {
        var output = ""
        for row in rows {
            let escaped = row.map { field -> String in
                if field.contains(delimiter) || field.contains("\"") || field.contains("\n") {
                    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return field
            }
            output += escaped.joined(separator: delimiter) + "\n"
        }
        try output.write(to: url, atomically: true, encoding: .utf8)
    }
}
