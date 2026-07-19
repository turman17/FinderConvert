import Foundation

public protocol ConversionEngine: Sendable {
    var identifier: String { get }
    func supports(
        input: DetectedFileType,
        output: OutputFormat
    ) -> Bool
    func convert(
        job: ConversionJob,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ConversionResult
    func cancel(jobID: UUID) async
}

public protocol ConversionRegistryProtocol: Sendable {
    func availableOutputs(for inputs: [DetectedFile]) -> [OutputFormat]
    func engine(for input: DetectedFileType, output: OutputFormat) -> any ConversionEngine
}
