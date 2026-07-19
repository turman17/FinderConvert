import Foundation

public struct FinderConvertRegistry: ConversionRegistryProtocol, Sendable {
    private let imageEngine: NativeImageConversionEngine
    private let pdfEngine: PdfConversionEngine
    private let videoEngine: VideoConversionEngine
    private let audioEngine: AudioConversionEngine
    private let documentEngine: DocumentConversionEngine
    private let spreadsheetEngine: SpreadsheetConversionEngine
    private let jsonEngine: JsonConversionEngine
    private let svgEngine: SvgConversionEngine
    private let epubEngine: EpubConversionEngine
    private let docxWriterEngine: DocxWriterEngine

    public init(
        imageEngine: NativeImageConversionEngine = NativeImageConversionEngine(),
        pdfEngine: PdfConversionEngine = PdfConversionEngine(),
        videoEngine: VideoConversionEngine = VideoConversionEngine(),
        audioEngine: AudioConversionEngine = AudioConversionEngine(),
        documentEngine: DocumentConversionEngine = DocumentConversionEngine(),
        spreadsheetEngine: SpreadsheetConversionEngine = SpreadsheetConversionEngine(),
        jsonEngine: JsonConversionEngine = JsonConversionEngine(),
        svgEngine: SvgConversionEngine = SvgConversionEngine(),
        epubEngine: EpubConversionEngine = EpubConversionEngine(),
        docxWriterEngine: DocxWriterEngine = DocxWriterEngine()
    ) {
        self.imageEngine = imageEngine
        self.pdfEngine = pdfEngine
        self.videoEngine = videoEngine
        self.audioEngine = audioEngine
        self.documentEngine = documentEngine
        self.spreadsheetEngine = spreadsheetEngine
        self.jsonEngine = jsonEngine
        self.svgEngine = svgEngine
        self.epubEngine = epubEngine
        self.docxWriterEngine = docxWriterEngine
    }

    public func availableOutputs(for inputs: [DetectedFile]) -> [OutputFormat] {
        guard !inputs.isEmpty else { return [] }

        var commonSupported = Set<OutputFormat>()

        for input in inputs {
            let supportedForInput = OutputFormat.allCases.filter { outputFormat in
                outputFormat.rawValue != input.detectedType.rawValue
                && engine(for: input.detectedType, output: outputFormat).identifier != "com.finderconvert.engine.unsupported"
            }
            commonSupported.formUnion(supportedForInput)
        }

        return OutputFormat.allCases.filter { commonSupported.contains($0) }
    }

    public func engine(for input: DetectedFileType, output: OutputFormat) -> any ConversionEngine {
        if imageEngine.supports(input: input, output: output) {
            return imageEngine
        }
        if pdfEngine.supports(input: input, output: output) {
            return pdfEngine
        }
        if videoEngine.supports(input: input, output: output) {
            return videoEngine
        }
        if audioEngine.supports(input: input, output: output) {
            return audioEngine
        }
        if documentEngine.supports(input: input, output: output) {
            return documentEngine
        }
        if spreadsheetEngine.supports(input: input, output: output) {
            return spreadsheetEngine
        }
        if jsonEngine.supports(input: input, output: output) {
            return jsonEngine
        }
        if svgEngine.supports(input: input, output: output) {
            return svgEngine
        }
        if epubEngine.supports(input: input, output: output) {
            return epubEngine
        }
        if docxWriterEngine.supports(input: input, output: output) {
            return docxWriterEngine
        }
        return UnsupportedConversionEngine()
    }
}

private struct UnsupportedConversionEngine: ConversionEngine {
    let identifier = "com.finderconvert.engine.unsupported"

    func supports(input: DetectedFileType, output: OutputFormat) -> Bool {
        false
    }

    func convert(
        job: ConversionJob,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ConversionResult {
        throw ConversionError.unsupportedOutput(job.requestedOutput)
    }

    func cancel(jobID: UUID) async {}
}
