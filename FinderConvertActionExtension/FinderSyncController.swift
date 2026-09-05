import Cocoa
import FinderSync
import OSLog
import FinderConvertCore

private let logger = Logger(subsystem: "FinderConvert", category: "findersync")

class FinderSyncController: FIFinderSync {

    override init() {
        super.init()
        logger.info("FinderSyncController launched")
        let rootURL = URL(fileURLWithPath: "/")
        FIFinderSyncController.default().directoryURLs = [rootURL]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        guard menuKind == .contextualMenuForItems else { return NSMenu(title: "") }
        
        guard let selectedURLs = FIFinderSyncController.default().selectedItemURLs(), !selectedURLs.isEmpty else {
            return NSMenu(title: "")
        }
        
        let isDirectory: (URL) -> Bool = { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        let containsFolder = selectedURLs.contains(where: isDirectory)

        let availableOutputs: [OutputFormat]
        if containsFolder {
            // The sandbox blocks this process from enumerating folder
            // contents, so ask the main app over the local query port; try a
            // direct sample first for the locations the sandbox does allow
            // (e.g. Downloads). If neither works - app not running - offer
            // every format and let the conversion sort the files out
            let local = QuickActionConversionService().sampledOutputs(for: selectedURLs)
            if !local.isEmpty {
                availableOutputs = local
                logger.info("folder menu via local sample: \(local.map { $0.rawValue })")
            } else if let remote = MenuQuery.sampledOutputs(for: selectedURLs), !remote.isEmpty {
                availableOutputs = remote
                logger.info("folder menu via app query: \(remote.map { $0.rawValue })")
            } else {
                availableOutputs = OutputFormat.allCases
                logger.info("folder menu fallback: all formats")
            }
        } else {
            do {
                let service = QuickActionConversionService()
                availableOutputs = try service.availableOutputs(for: selectedURLs)
                logger.info("availableOutputs for \(selectedURLs.first?.path ?? ""): \(availableOutputs.map { $0.rawValue })")
            } catch {
                logger.error("availableOutputs threw error: \(error.localizedDescription)")
                availableOutputs = []
            }
        }

        // If there are no valid output formats for the selection, don't show the Convert menu at all
        if availableOutputs.isEmpty {
            return NSMenu(title: "")
        }

        let menu = NSMenu(title: "")
        let isFolder = selectedURLs.count == 1 && isDirectory(selectedURLs[0])
        let title = isFolder ? "Convert Folder" : (selectedURLs.count > 1 ? "Convert \(selectedURLs.count) Files" : "Convert File")
        let convertItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Convert Formats")

        let formats = PreferencesManager.shared.enabledFormats.filter { availableOutputs.contains($0) }

        for format in formats {
            let sel = selector(for: format)
            let item = NSMenuItem(title: format.displayName, action: sel, keyEquivalent: "")
            item.target = self
            submenu.addItem(item)
        }

        // PDF tools: Merge (multiple PDFs) and Split (single PDF)
        let allPDFs = selectedURLs.allSatisfy { $0.pathExtension.lowercased() == "pdf" }
        if allPDFs && selectedURLs.count >= 2 {
            submenu.addItem(NSMenuItem.separator())
            let mergeItem = NSMenuItem(title: "Merge PDFs", action: #selector(mergePDFs(_:)), keyEquivalent: "")
            mergeItem.target = self
            submenu.addItem(mergeItem)
        }
        if allPDFs && selectedURLs.count == 1 {
            submenu.addItem(NSMenuItem.separator())
            let splitItem = NSMenuItem(title: "Split PDF (one page per file)", action: #selector(splitPDF(_:)), keyEquivalent: "")
            splitItem.target = self
            submenu.addItem(splitItem)
        }

        submenu.addItem(NSMenuItem.separator())
        let configItem = NSMenuItem(title: "Configure Formats...", action: #selector(configureFormats(_:)), keyEquivalent: "")
        configItem.target = self
        submenu.addItem(configItem)

        convertItem.submenu = submenu
        menu.addItem(convertItem)

        return menu
    }
    
    private func selector(for format: OutputFormat) -> Selector {
        switch format {
        case .jpeg: return #selector(convertToJPEG(_:))
        case .png: return #selector(convertToPNG(_:))
        case .heic: return #selector(convertToHEIC(_:))
        case .tiff: return #selector(convertToTIFF(_:))
        case .gif: return #selector(convertToGIF(_:))
        case .bmp: return #selector(convertToBMP(_:))
        case .ico: return #selector(convertToICO(_:))
        case .avif: return #selector(convertToAVIF(_:))
        case .webp: return #selector(convertToWEBP(_:))
        case .mp4: return #selector(convertToMP4(_:))
        case .mov: return #selector(convertToMOV(_:))
        case .hevc: return #selector(convertToHEVC(_:))
        case .mp3: return #selector(convertToMP3(_:))
        case .m4a: return #selector(convertToM4A(_:))
        case .wav: return #selector(convertToWAV(_:))
        case .aiff: return #selector(convertToAIFF(_:))
        case .flac: return #selector(convertToFLAC(_:))
        case .pdf: return #selector(convertToPDF(_:))
        case .rtf: return #selector(convertToRTF(_:))
        case .html: return #selector(convertToHTML(_:))
        case .txt: return #selector(convertToTXT(_:))
        case .csv: return #selector(convertToCSV(_:))
        case .tsv: return #selector(convertToTSV(_:))
        case .xlsx: return #selector(convertToXLSX(_:))
        case .docx: return #selector(convertToDOCX(_:))
        }
    }
    
    private var sharedFilePath: URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("Could not resolve document directory, falling back to temporary directory")
            return FileManager.default.temporaryDirectory.appendingPathComponent("pending_actions.json")
        }
        return docs.appendingPathComponent("pending_actions.json")
    }

    @objc func configureFormats(_ sender: Any?) {
        let filePath = self.sharedFilePath
        Task { @MainActor in
            let action = ["action": "configure"]
            do {
                let data = try JSONSerialization.data(withJSONObject: action)
                try data.write(to: filePath, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath.path)
            } catch {
                logger.error("Failed to write action file: \(error.localizedDescription, privacy: .public)")
            }
            let appURL = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            
            let bundleIdentifier = "com.finderconvert.app"
            let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
            
            if isRunning {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name("com.finderconvert.app.Wakeup"),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
            } else {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
                    if let error = error {
                        logger.error("Failed to open app: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func performConversion(to targetFormat: String) {
        logger.info("performConversion called for target format: \(targetFormat, privacy: .public)")
        
        guard let selectedURLs = FIFinderSyncController.default().selectedItemURLs(), !selectedURLs.isEmpty else {
            logger.error("No selected item URLs found!")
            return
        }
        logger.info("Found \(selectedURLs.count) selected URLs.")

        let filePath = self.sharedFilePath
        let filePaths = selectedURLs.map { $0.path }
        
        Task { @MainActor in
            let action: [String: Any] = [
                "action": "convert",
                "targetFormatId": targetFormat,
                "filePaths": filePaths
            ]
            
            do {
                let data = try JSONSerialization.data(withJSONObject: action)
                try data.write(to: filePath, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath.path)
            } catch {
                logger.error("Failed to write action file: \(error.localizedDescription, privacy: .public)")
                return
            }

            let appURL = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()

            let bundleIdentifier = "com.finderconvert.app"
            let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty

            if isRunning {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name("com.finderconvert.app.Wakeup"),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
                logger.info("App is already running. Sent distributed notification.")
            } else {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
                    if let error = error {
                        logger.error("Failed to open app: \(error.localizedDescription)")
                    } else {
                        logger.info("Successfully asked main app to open.")
                    }
                }
            }
        }
    }

    @objc func mergePDFs(_ sender: Any?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), urls.count >= 2 else { return }
        performAction("merge_pdf", filePaths: urls.map { $0.path })
    }

    @objc func splitPDF(_ sender: Any?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), urls.count == 1 else { return }
        performAction("split_pdf", filePaths: [urls[0].path])
    }

    private func performAction(_ action: String, filePaths: [String]) {
        let filePath = self.sharedFilePath
        Task { @MainActor in
            let payload: [String: Any] = ["action": action, "filePaths": filePaths]
            do {
                let data = try JSONSerialization.data(withJSONObject: payload)
                try data.write(to: filePath, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath.path)
            } catch {
                logger.error("Failed to write action file: \(error.localizedDescription, privacy: .public)")
                return
            }

            let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let bundleIdentifier = "com.finderconvert.app"
            let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty

            if isRunning {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name("com.finderconvert.app.Wakeup"), object: nil, userInfo: nil, deliverImmediately: true)
            } else {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                    if let error { logger.error("Failed to open app: \(error.localizedDescription)") }
                }
            }
        }
    }

    @objc func convertToJPEG(_ sender: Any?) { performConversion(to: "jpeg") }
    @objc func convertToPNG(_ sender: Any?) { performConversion(to: "png") }
    @objc func convertToHEIC(_ sender: Any?) { performConversion(to: "heic") }
    @objc func convertToTIFF(_ sender: Any?) { performConversion(to: "tiff") }
    @objc func convertToGIF(_ sender: Any?) { performConversion(to: "gif") }
    @objc func convertToBMP(_ sender: Any?) { performConversion(to: "bmp") }
    @objc func convertToICO(_ sender: Any?) { performConversion(to: "ico") }
    @objc func convertToAVIF(_ sender: Any?) { performConversion(to: "avif") }
    @objc func convertToWEBP(_ sender: Any?) { performConversion(to: "webp") }
    @objc func convertToMP4(_ sender: Any?) { performConversion(to: "mp4") }
    @objc func convertToMOV(_ sender: Any?) { performConversion(to: "mov") }
    @objc func convertToHEVC(_ sender: Any?) { performConversion(to: "hevc") }
    @objc func convertToMP3(_ sender: Any?) { performConversion(to: "mp3") }
    @objc func convertToM4A(_ sender: Any?) { performConversion(to: "m4a") }
    @objc func convertToWAV(_ sender: Any?) { performConversion(to: "wav") }
    @objc func convertToAIFF(_ sender: Any?) { performConversion(to: "aiff") }
    @objc func convertToFLAC(_ sender: Any?) { performConversion(to: "flac") }
    @objc func convertToPDF(_ sender: Any?) { performConversion(to: "pdf") }
    @objc func convertToRTF(_ sender: Any?) { performConversion(to: "rtf") }
    @objc func convertToHTML(_ sender: Any?) { performConversion(to: "html") }
    @objc func convertToTXT(_ sender: Any?) { performConversion(to: "txt") }
    @objc func convertToCSV(_ sender: Any?) { performConversion(to: "csv") }
    @objc func convertToTSV(_ sender: Any?) { performConversion(to: "tsv") }
    @objc func convertToXLSX(_ sender: Any?) { performConversion(to: "xlsx") }
    @objc func convertToDOCX(_ sender: Any?) { performConversion(to: "docx") }
}
