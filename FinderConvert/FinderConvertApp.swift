import SwiftUI
import UserNotifications
import FinderConvertCore
import OSLog
import AppKit
import Combine

extension Notification.Name {
    static let navigateToTab = Notification.Name("FinderConvert.navigateToTab")
}

// MARK: - Menu Bar Popover View

struct MenuBarDropView: View {
    let appDelegate: AppDelegate
    @State private var droppedFiles: [URL] = []
    @State private var isTargeted = false
    @State private var selectedFormat: String = OutputFormat.jpeg.rawValue
    @State private var availableFormats: [OutputFormat] = OutputFormat.allCases.map { $0 }
    @State private var convertingStatus: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("FinderConvert")
                    .font(.headline)
                Spacer()
                if appDelegate.activeConversion != nil {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                        style: StrokeStyle(lineWidth: 1, dash: droppedFiles.isEmpty ? [4] : [])
                    )

                if droppedFiles.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 16))
                            .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                        Text("Drop files here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 2) {
                        HStack {
                            Text("\(droppedFiles.count) file\(droppedFiles.count == 1 ? "" : "s")")
                                .font(.caption2.weight(.semibold))
                            Spacer()
                            Button { withAnimation { droppedFiles.removeAll(); refreshFormats() } } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 3)

                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(droppedFiles, id: \.self) { url in
                                    HStack(spacing: 4) {
                                        Text(url.lastPathComponent)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        Text(url.pathExtension.uppercased())
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                }
                            }
                        }
                        .padding(.bottom, 3)
                    }
                }
            }
            .frame(height: droppedFiles.isEmpty ? 54 : 68)
            .padding(.horizontal, 10)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }

            // Format + Convert
            if !droppedFiles.isEmpty {
                HStack(spacing: 6) {
                    Picker("", selection: $selectedFormat) {
                        ForEach(availableFormats, id: \.rawValue) { format in
                            Text(format.displayName).tag(format.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button {
                        convertFiles()
                    } label: {
                        Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(appDelegate.activeConversion != nil)
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }

            // Status message
            if let status = convertingStatus {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .transition(.opacity)
            }

            Divider()
                .padding(.top, 6)

            // Quick links
            VStack(spacing: 0) {
                menuButton("Open App", icon: "macwindow") { appDelegate.showConverter() }
                menuButton("History", icon: "clock.arrow.circlepath") { appDelegate.showHistory() }
                menuButton("Settings", icon: "gearshape") { appDelegate.showSettings() }
            }

            // Recent
            let history = ConversionHistoryStore.shared.entries.prefix(2)
            if !history.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recent")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                    ForEach(Array(history), id: \.id) { entry in
                        Button {
                            // Open the output file in Finder
                            if let path = entry.outputFiles.first {
                                let url = URL(fileURLWithPath: path)
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            appDelegate.menuBarPopover?.performClose(nil)
                        } label: {
                            HStack {
                                Text(entry.inputFiles.first ?? "")
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(entry.outputFormat)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Update available
            if let update = appDelegate.availableUpdate {
                Divider()
                Button {
                    if let url = UpdateChecker.shared.downloadURL(from: update) {
                        NSWorkspace.shared.open(url)
                    }
                    appDelegate.menuBarPopover?.performClose(nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                        Text("Update available: \(update.tagName)")
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.green.opacity(0.08))
                    )
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Quit
            menuButton("Quit", icon: "xmark.circle") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 2)
        }
        .frame(width: 240)
        .padding(.bottom, 4)
        .onReceive(NotificationCenter.default.publisher(for: .filesDroppedOnMenuBar)) { notification in
            if let urls = notification.object as? [URL] {
                withAnimation { droppedFiles.append(contentsOf: urls) }
                refreshFormats()
            }
        }
    }

    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            appDelegate.menuBarPopover?.performClose(nil)
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 14)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var newURLs: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data, let str = String(data: data, encoding: .utf8), let url = URL(string: str) {
                    DispatchQueue.main.async { newURLs.append(url) }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            withAnimation { droppedFiles.append(contentsOf: newURLs) }
            refreshFormats()
        }
        return true
    }

    private func refreshFormats() {
        if droppedFiles.isEmpty {
            availableFormats = OutputFormat.allCases.map { $0 }
            return
        }
        let service = QuickActionConversionService()
        if let outputs = try? service.availableOutputs(for: droppedFiles), !outputs.isEmpty {
            availableFormats = outputs
            if !outputs.contains(where: { $0.rawValue == selectedFormat }) {
                selectedFormat = outputs.first?.rawValue ?? OutputFormat.jpeg.rawValue
            }
        }
    }

    private func convertFiles() {
        guard !droppedFiles.isEmpty else { return }
        let urls = droppedFiles
        let format = selectedFormat
        withAnimation { droppedFiles.removeAll() }
        appDelegate.runConversion(for: urls, targetFormatId: format)
        withAnimation { convertingStatus = "Converting..." }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { convertingStatus = nil }
        }
    }
}

// MARK: - Menu Bar Drop Target (icon drag)

class StatusBarDropView: NSView {
    weak var appDelegate: AppDelegate?

    init(frame: NSRect, appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Highlight the status bar button
        if let button = superview as? NSStatusBarButton {
            button.isHighlighted = true
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let button = superview as? NSStatusBarButton {
            button.isHighlighted = false
        }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let button = superview as? NSStatusBarButton {
            button.isHighlighted = false
        }

        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else { return false }

        Task { @MainActor [weak self] in
            guard let self, let appDelegate = self.appDelegate else { return }
            // Open the popover and pass files into it
            appDelegate.toggleMenuBarPopover()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .filesDroppedOnMenuBar, object: urls)
            }
        }

        return true
    }
}

extension Notification.Name {
    static let filesDroppedOnMenuBar = Notification.Name("FinderConvert.filesDroppedOnMenuBar")
}

struct ActiveConversion {
    let description: String
    let startTime: Date = .now
    var progress: Double = 0
    var isComplete = false
}

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate, ObservableObject {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    let conversionService = QuickActionConversionService()
    let pdfTools = PdfToolsService()
    let logger = Logger(subsystem: "FinderConvert", category: "main-app")
    var preferencesWindowController: NSWindowController?
    var statusItem: NSStatusItem?
    @Published var activeConversion: ActiveConversion? {
        didSet { updateMenuBarMenu() }
    }
    @Published var historyRefreshTrigger = false {
        didSet { updateMenuBarMenu() }
    }
    @Published var lastResults: [ConversionResult] = []
    @Published var availableUpdate: GitHubRelease?

    var sharedDefaults: UserDefaults?

    private var sharedFilePath: URL {
        let homeDir = URL(fileURLWithPath: NSHomeDirectory())
        return homeDir.appendingPathComponent("Library/Containers/com.finderconvert.app.ActionExtension/Data/Documents/pending_actions.json")
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupMenuBarIcon()
        UNUserNotificationCenter.current().delegate = self
        Task {
            await requestNotificationAuthorization()
        }
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: NSNotification.Name("com.finderconvert.app.Wakeup"),
            object: nil
        )
        
        checkPendingActions()
        registerAsLoginItem()

        // Check for updates
        Task {
            if let release = await UpdateChecker.shared.checkForUpdate() {
                await MainActor.run { self.availableUpdate = release }
            }
        }

        // Show onboarding on first launch
        if !PreferencesManager.shared.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    @objc private func handleDistributedNotification(_ notification: Notification) {
        logger.info("Received distributed wakeup notification")
        checkPendingActions()
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        logger.info("Main app asked to open URL: \(url, privacy: .public)")
        guard url.scheme == "finderconvert", url.host == "wakeup" else { return }
        let _ = checkPendingActions()
    }
    
    @discardableResult
    private func checkPendingActions() -> Bool {
        guard FileManager.default.fileExists(atPath: sharedFilePath.path) else { return false }

        let data: Data
        let json: [String: Any]
        let action: String
        do {
            data = try Data(contentsOf: sharedFilePath)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parsedAction = parsed["action"] as? String else {
                logger.error("Pending action file has invalid format")
                return false
            }
            json = parsed
            action = parsedAction
        } catch {
            logger.error("Failed to read pending action: \(error.localizedDescription, privacy: .public)")
            return false
        }

        do {
            try FileManager.default.removeItem(at: sharedFilePath)
        } catch {
            logger.warning("Failed to remove pending action file: \(error.localizedDescription, privacy: .public)")
        }
        
        if action == "configure" {
            openPreferencesWindow()
            navigateToTab(.formats)
            return true
        } else if action == "convert" {
            if let targetFormatId = json["targetFormatId"] as? String,
               let filePaths = json["filePaths"] as? [String] {
                let fileURLs = filePaths.map { URL(fileURLWithPath: $0) }
                runConversion(for: fileURLs, targetFormatId: targetFormatId)
                return true
            }
        } else if action == "merge_pdf" {
            if let filePaths = json["filePaths"] as? [String] {
                let fileURLs = filePaths.map { URL(fileURLWithPath: $0) }
                runMergePDF(urls: fileURLs)
                return true
            }
        } else if action == "split_pdf" {
            if let filePaths = json["filePaths"] as? [String], let first = filePaths.first {
                runSplitPDF(url: URL(fileURLWithPath: first))
                return true
            }
        }
        return false
    }

    var menuBarPanel: NSPanel?
    var menuBarPopover: NSPopover? // keep for compatibility

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let img = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "FinderConvert")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "FinderConvert — drop files to convert"
            button.action = #selector(toggleMenuBarPopover)
            button.target = self

            let dropView = StatusBarDropView(frame: button.bounds, appDelegate: self)
            dropView.autoresizingMask = [.width, .height]
            button.addSubview(dropView)
        }
    }

    @objc func toggleMenuBarPopover() {
        if let popover = menuBarPopover, popover.isShown {
            popover.performClose(nil)
            return
        }

        guard let button = statusItem?.button else { return }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let controller = NSHostingController(rootView: MenuBarDropView(appDelegate: self))
        controller.view.setFrameSize(NSSize(width: 220, height: 1))
        let fitting = controller.view.fittingSize
        popover.contentSize = NSSize(width: 220, height: fitting.height)
        popover.contentViewController = controller

        self.menuBarPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func updateMenuBarMenu() {
        if let button = statusItem?.button {
            let symbolName = activeConversion != nil ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath"
            let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "FinderConvert")
            img?.isTemplate = true
            button.image = img
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (FinderConvert)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About FinderConvert", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide FinderConvert", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit FinderConvert", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Converter", action: #selector(showConverter), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "Formats", action: #selector(showFormats), keyEquivalent: "2")
        viewMenu.addItem(withTitle: "History", action: #selector(showHistory), keyEquivalent: "3")
        viewMenu.addItem(withTitle: "Settings", action: #selector(showSettings), keyEquivalent: "4")
        viewMenu.addItem(withTitle: "Docs", action: #selector(showDocs), keyEquivalent: "5")
        viewMenu.addItem(withTitle: "About", action: #selector(showAbout), keyEquivalent: "6")
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // Help menu
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "FinderConvert Docs", action: #selector(showDocs), keyEquivalent: "?")
        helpMenu.addItem(NSMenuItem.separator())
        helpMenu.addItem(withTitle: "Enable Finder Extension", action: #selector(openExtensionSettings), keyEquivalent: "")
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc func showConverter() {
        openPreferencesWindow()
        navigateToTab(.converter)
    }

    @objc func showFormats() {
        openPreferencesWindow()
        navigateToTab(.formats)
    }

    @objc func showHistory() {
        openPreferencesWindow()
        navigateToTab(.history)
    }

    @objc func showSettings() {
        openPreferencesWindow()
        navigateToTab(.settings)
    }

    @objc func showDocs() {
        openPreferencesWindow()
        navigateToTab(.docs)
    }

    @objc func showAbout() {
        openPreferencesWindow()
        navigateToTab(.about)
    }

    @objc private func openExtensionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
    }

    private func navigateToTab(_ tab: SidebarItem) {
        NotificationCenter.default.post(name: .navigateToTab, object: tab)
    }

    func openPreferencesWindow() {
        NSApplication.shared.setActivationPolicy(.regular)

        if let windowController = preferencesWindowController {
            windowController.showWindow(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("FinderConvertMain")
        window.title = "FinderConvert"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 580, height: 400)
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainView(appDelegate: self))

        let windowController = NSWindowController(window: window)
        self.preferencesWindowController = windowController
        windowController.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var onboardingWindowController: NSWindowController?

    func showOnboarding() {
        NSApplication.shared.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.title = "Welcome to FinderConvert"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(onComplete: { [weak self] in
            PreferencesManager.shared.hasCompletedOnboarding = true
            self?.onboardingWindowController?.close()
            self?.onboardingWindowController = nil
            NSApplication.shared.setActivationPolicy(.accessory)
        }))
        let controller = NSWindowController(window: window)
        onboardingWindowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func registerAsLoginItem() {
        let script = "tell application \"System Events\"\nif not (exists login item \"FinderConvert\") then\nmake login item at end with properties {path:\"/Applications/FinderConvert.app\", hidden:true}\nend if\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                logger.warning("Login item registration: \(error)")
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Hide from Dock when window closes — app stays running via menu bar icon
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func requestNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep app alive in background
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPreferencesWindow()
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private static let largeFileThreshold: Int64 = 1_000_000 // 1 MB

    func runConversion(for urls: [URL], targetFormatId: String?, renameMap: [URL: String] = [:]) {
        Task {
            do {
                let outputs: [OutputFormat]
                do {
                    outputs = try conversionService.availableOutputs(for: urls)
                } catch {
                    logger.error("availableOutputs threw: \(error.localizedDescription, privacy: .public)")
                    throw error
                }

                guard let targetFormatId = targetFormatId,
                      let targetOutput = outputs.first(where: { $0.rawValue == targetFormatId }) else {
                    logger.error("Requested format is not supported or was missing.")
                    await postFailureNotification(message: "The requested format is not supported for these files.")
                    return
                }

                let totalSize = urls.reduce(into: Int64(0)) { sum, url in
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    sum += Int64(size)
                }
                let isLarge = totalSize >= Self.largeFileThreshold

                let fileDesc = urls.count == 1 ? "1 file" : "\(urls.count) files"
                activeConversion = ActiveConversion(description: "Converting \(fileDesc) to \(targetOutput.displayName)")

                if isLarge {
                    await postStartedNotification(fileDesc: fileDesc, format: targetOutput.displayName)
                }

                logger.info("Converting to \(targetOutput.displayName)...")
                let result: BatchConversionResult
                do {
                    result = try await conversionService.convert(urls: urls, requestedOutput: targetOutput)
                } catch {
                    logger.error("convert threw: \(error.localizedDescription, privacy: .public)")
                    throw error
                }

                // Apply renames if provided
                var finalOutputPaths: [String] = []
                for success in result.successes {
                    let sourceURL = success.sourceURL
                    if let customName = renameMap[sourceURL] {
                        let outputURL = success.outputURL
                        let ext = outputURL.pathExtension
                        let renamedURL = outputURL.deletingLastPathComponent().appendingPathComponent("\(customName).\(ext)")
                        if !FileManager.default.fileExists(atPath: renamedURL.path(percentEncoded: false)) {
                            try? FileManager.default.moveItem(at: outputURL, to: renamedURL)
                            finalOutputPaths.append(renamedURL.path)
                        } else {
                            finalOutputPaths.append(outputURL.path)
                        }
                    } else {
                        finalOutputPaths.append(success.outputURL.path)
                    }
                }

                // Record history
                let outputSize = result.successes.reduce(into: Int64(0)) { sum, r in
                    sum += Int64((try? FileManager.default.attributesOfItem(atPath: r.outputURL.path)[.size] as? Int) ?? 0)
                }
                ConversionHistoryStore.shared.add(ConversionHistoryEntry(
                    action: "convert",
                    inputFiles: urls.map { $0.lastPathComponent },
                    outputFiles: finalOutputPaths,
                    outputFormat: targetOutput.displayName,
                    totalInputSize: totalSize,
                    totalOutputSize: outputSize,
                    success: result.failures.isEmpty,
                    errorMessage: result.failures.first?.error.localizedDescription
                ))
                historyRefreshTrigger.toggle()

                activeConversion = nil
                lastResults = result.successes

                if isLarge {
                    try? await postNotification(for: result)
                }
                logger.info("Conversion completed.")

            } catch {
                activeConversion = nil
                logger.error("Conversion failed overall: \(error.localizedDescription, privacy: .public)")
                await postFailureNotification(message: error.localizedDescription)
            }
        }
    }

    func runMergePDF(urls: [URL]) {
        Task {
            activeConversion = ActiveConversion(description: "Merging \(urls.count) PDFs")
            do {
                let outputURL = try pdfTools.merge(urls: urls)
                let inputSize = urls.reduce(into: Int64(0)) { sum, url in
                    sum += Int64((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
                }
                let outputSize = Int64((try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0)
                ConversionHistoryStore.shared.add(ConversionHistoryEntry(
                    action: "merge",
                    inputFiles: urls.map { $0.lastPathComponent },
                    outputFiles: [outputURL.path],
                    outputFormat: "PDF (merged)",
                    totalInputSize: inputSize, totalOutputSize: outputSize, success: true
                ))
                historyRefreshTrigger.toggle()
                activeConversion = nil
                await postCompletionNotification(title: "PDFs Merged", body: "\(urls.count) files → \(outputURL.lastPathComponent)")
            } catch {
                activeConversion = nil
                logger.error("PDF merge failed: \(error.localizedDescription, privacy: .public)")
                await postFailureNotification(message: error.localizedDescription)
            }
        }
    }

    func runSplitPDF(url: URL) {
        Task {
            activeConversion = ActiveConversion(description: "Splitting \(url.lastPathComponent)")
            do {
                let outputURLs = try pdfTools.split(url: url)
                let inputSize = Int64((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
                let outputSize = outputURLs.reduce(into: Int64(0)) { sum, u in
                    sum += Int64((try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0)
                }
                ConversionHistoryStore.shared.add(ConversionHistoryEntry(
                    action: "split",
                    inputFiles: [url.lastPathComponent],
                    outputFiles: outputURLs.map { $0.path },
                    outputFormat: "PDF (split)",
                    totalInputSize: inputSize, totalOutputSize: outputSize, success: true
                ))
                historyRefreshTrigger.toggle()
                activeConversion = nil
                await postCompletionNotification(title: "PDF Split", body: "\(outputURLs.count) pages extracted from \(url.lastPathComponent)")
            } catch {
                activeConversion = nil
                logger.error("PDF split failed: \(error.localizedDescription, privacy: .public)")
                await postFailureNotification(message: error.localizedDescription)
            }
        }
    }

    private func postCompletionNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await deliverNotification(content)
    }

    private func postNotification(for result: BatchConversionResult) async throws {
        let content = UNMutableNotificationContent()
        if result.failures.isEmpty {
            let title = result.successes.count == 1 ? "Converted 1 file." : "Converted \(result.successes.count) files."
            content.title = title
            content.body = "Output format: \(result.requestedOutput.displayName)."
        } else if result.successes.isEmpty {
            content.title = "Conversion failed."
            content.body = result.failures.first?.error.localizedDescription ?? "FinderConvert could not convert the selected files."
        } else {
            content.title = "Converted \(result.successes.count) of \(result.successes.count + result.failures.count) files."
            content.body = "\(result.failures.count) file(s) could not be converted."
        }
        try await deliverNotification(content)
    }

    private func postStartedNotification(fileDesc: String, format: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Converting \(fileDesc)..."
        content.body = "Converting to \(format). This may take a moment."
        try? await deliverNotification(content)
    }

    private func postFailureNotification(message: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Conversion failed."
        content.body = message
        try? await deliverNotification(content)
    }

    private func deliverNotification(_ content: UNMutableNotificationContent) async throws {
        let center = UNUserNotificationCenter.current()
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try await center.add(request)
    }
}

// MARK: - Navigation

enum SidebarItem: String, CaseIterable, Identifiable {
    case converter = "Converter"
    case formats = "Formats"
    case history = "History"
    case settings = "Settings"
    case docs = "Docs"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .converter: return "arrow.triangle.2.circlepath"
        case .formats: return "checklist"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .docs: return "book"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Main View

struct MainView: View {
    @ObservedObject var appDelegate: AppDelegate
    @State private var selectedItem: SidebarItem = .converter

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
        } detail: {
            Group {
                switch selectedItem {
                case .converter:
                    ConverterTab(appDelegate: appDelegate)
                case .formats:
                    FormatsTab()
                case .history:
                    HistoryTab(appDelegate: appDelegate)
                case .settings:
                    SettingsTab()
                case .docs:
                    DocsTab()
                case .about:
                    AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { notification in
            if let tab = notification.object as? SidebarItem {
                selectedItem = tab
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selection: SidebarItem

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarItem.allCases) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .font(.body)
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
    }
}

// MARK: - Converter

struct DroppedFileRow: View {
    let file: DroppedFile
    let availableFormats: [OutputFormat]
    let showFormatPicker: Bool
    let onRename: (String) -> Void
    let onFormatChange: (String?) -> Void
    let onRemove: () -> Void
    @State private var editName: String
    @State private var fileFormat: String

    init(file: DroppedFile, availableFormats: [OutputFormat] = [], showFormatPicker: Bool = false,
         onRename: @escaping (String) -> Void, onFormatChange: @escaping (String?) -> Void = { _ in }, onRemove: @escaping () -> Void) {
        self.file = file
        self.availableFormats = availableFormats
        self.showFormatPicker = showFormatPicker
        self.onRename = onRename
        self.onFormatChange = onFormatChange
        self.onRemove = onRemove
        self._editName = State(initialValue: file.outputName)
        self._fileFormat = State(initialValue: file.formatOverride ?? "")
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconForFile(file.url))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            TextField("", text: $editName, onCommit: { onRename(editName) })
                .font(.system(.caption, design: .default))
                .textFieldStyle(.plain)
                .lineLimit(1)
                .onChange(of: editName) { _, val in onRename(val) }
            Text(".\(file.url.pathExtension)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if showFormatPicker && !availableFormats.isEmpty {
                Text("→")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Picker("", selection: $fileFormat) {
                    ForEach(availableFormats, id: \.rawValue) { fmt in
                        Text(fmt.displayName).tag(fmt.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 70)
                .controlSize(.small)
                .onChange(of: fileFormat) { _, val in
                    onFormatChange(val.isEmpty ? nil : val)
                }
            }
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp", "svg", "avif", "ico", "webp": return "photo"
        case "mp4", "mov", "webm": return "film"
        case "mp3", "m4a", "wav", "aiff", "flac": return "waveform"
        case "pdf": return "doc.text"
        case "epub": return "book"
        default: return "doc"
        }
    }
}

struct DroppedFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var outputName: String
    var formatOverride: String? // per-file format (nil = use global)

    init(url: URL) {
        self.url = url
        self.outputName = url.deletingPathExtension().lastPathComponent
        self.formatOverride = nil
    }
}

struct ConverterTab: View {
    @ObservedObject var appDelegate: AppDelegate
    @State private var isTargeted = false
    @State private var selectedFormatId: String = OutputFormat.jpeg.rawValue
    @State private var droppedFiles: [DroppedFile] = []
    @State private var availableFormats: [OutputFormat] = OutputFormat.allCases.map { $0 }
    @State private var useCustomOutput = PreferencesManager.shared.useCustomOutputFolder
    @State private var customOutputPath: String = PreferencesManager.shared.customOutputFolder?.path ?? ""
    @State private var showPresets = false
    @State private var presetName = ""
    @State private var activePresetName = ""
    @State private var convertedResults: [ConversionResult] = []

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar during conversion
            if appDelegate.activeConversion != nil {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appDelegate.activeConversion?.description ?? "Converting...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Results view (after conversion)
            if !convertedResults.isEmpty && droppedFiles.isEmpty && appDelegate.activeConversion == nil {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(convertedResults.count) file\(convertedResults.count == 1 ? "" : "s") converted")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            withAnimation { convertedResults.removeAll() }
                        } label: {
                            Text("Clear")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(convertedResults, id: \.outputURL) { result in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 14)
                                    Text(result.outputURL.lastPathComponent)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                                    } label: {
                                        Image(systemName: "magnifyingglass.circle")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Reveal in Finder")
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.writeObjects([result.outputURL as NSURL])
                                    } label: {
                                        Image(systemName: "doc.on.clipboard")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy file path")
                                }
                                .padding(.horizontal, 32)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
                .padding(.bottom, 8)
            }

            Spacer(minLength: 12)

            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.primary.opacity(0.08),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6])
                    )

                if droppedFiles.isEmpty {
                    Button { openFilePicker() } label: {
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                                    .frame(width: 56, height: 56)
                                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                            }
                            Text("Drop files here or click to browse")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Images, videos, audio, documents, SVG, EPUB")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    // Per-file list + presets
                    VStack(spacing: 0) {
                        HStack {
                            Text("\(droppedFiles.count) file\(droppedFiles.count == 1 ? "" : "s")")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                withAnimation { droppedFiles.removeAll() }
                                refreshAvailableFormats()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(droppedFiles) { file in
                                    DroppedFileRow(
                                        file: file,
                                        availableFormats: availableFormats,
                                        showFormatPicker: droppedFiles.count > 1,
                                        onRename: { newName in
                                            if let idx = droppedFiles.firstIndex(where: { $0.id == file.id }) {
                                                droppedFiles[idx].outputName = newName
                                            }
                                        },
                                        onFormatChange: { fmt in
                                            if let idx = droppedFiles.firstIndex(where: { $0.id == file.id }) {
                                                droppedFiles[idx].formatOverride = fmt
                                            }
                                        },
                                        onRemove: {
                                            withAnimation { droppedFiles.removeAll { $0.id == file.id } }
                                            refreshAvailableFormats()
                                        }
                                    )
                                }
                            }
                        }

                        // Presets strip — only show relevant presets for dropped file types
                        let fileCategories = droppedFileCategories()
                        let relevantBuiltIn = PresetSettings.builtIn.filter { presetMatchesCategories($0.settings, fileCategories) }
                        let userPresets = PreferencesManager.shared.loadAllPresets()
                        let relevantUser = userPresets.filter { presetMatchesCategories($0.value, fileCategories) }

                        if !relevantBuiltIn.isEmpty || !relevantUser.isEmpty {
                            Divider().padding(.horizontal, 12).padding(.top, 4)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(relevantBuiltIn, id: \.name) { preset in
                                        presetPill(name: preset.name, icon: preset.icon, settings: preset.settings)
                                    }
                                    if !relevantUser.isEmpty {
                                        Divider().frame(height: 14)
                                        ForEach(Array(relevantUser.keys.sorted()), id: \.self) { name in
                                            if let p = relevantUser[name] {
                                                presetPill(name: name, icon: "slider.horizontal.3", settings: p)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: droppedFiles.isEmpty ? 180 : 260)
            .padding(.horizontal, 32)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
            .animation(.easeInOut(duration: 0.2), value: isTargeted)

            Spacer(minLength: 8)

            // Output folder
            HStack(spacing: 6) {
                Toggle("", isOn: $useCustomOutput)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .onChange(of: useCustomOutput) { _, val in
                        PreferencesManager.shared.useCustomOutputFolder = val
                    }
                Text(useCustomOutput ? (customOutputPath.isEmpty ? "Choose..." : URL(fileURLWithPath: customOutputPath).lastPathComponent) : "Save beside original")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if useCustomOutput {
                    Button("Browse") { pickOutputFolder() }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 6)


            // Format + Convert
            HStack(spacing: 12) {
                Picker(droppedFiles.count > 1 ? "Format all" : "Format", selection: $selectedFormatId) {
                    let grouped: [(String, [OutputFormat])] = [
                        ("Images", availableFormats.filter { $0.category == .image }),
                        ("Video", availableFormats.filter { $0.category == .video }),
                        ("Audio", availableFormats.filter { $0.category == .audio }),
                        ("Documents", availableFormats.filter { $0.category == .document }),
                    ].filter { !$0.1.isEmpty }
                    ForEach(grouped, id: \.0) { category, formats in
                        Section(category) {
                            ForEach(formats, id: \.rawValue) { format in
                                Text(format.displayName).tag(format.rawValue)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                Spacer()

                Button(action: convertFiles) {
                    Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(droppedFiles.isEmpty || appDelegate.activeConversion != nil)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
        .onReceive(NotificationCenter.default.publisher(for: .filesDroppedOnMenuBar)) { notification in
            if let urls = notification.object as? [URL] {
                let newFiles = urls.map { DroppedFile(url: $0) }
                withAnimation(.easeOut(duration: 0.15)) { droppedFiles.append(contentsOf: newFiles) }
                refreshAvailableFormats()
            }
        }
        .onChange(of: appDelegate.lastResults) { _, results in
            if !results.isEmpty {
                withAnimation { convertedResults = results }
            }
        }
    }

    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp", "svg", "avif", "ico": return "photo"
        case "mp4", "mov", "webm": return "film"
        case "mp3", "m4a", "wav", "aiff", "flac": return "waveform"
        case "pdf": return "doc.text"
        case "epub": return "book"
        default: return "doc"
        }
    }

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            customOutputPath = url.path
            PreferencesManager.shared.customOutputFolder = url
        }
    }

    private func presetPill(name: String, icon: String, settings: PresetSettings) -> some View {
        Button {
            PreferencesManager.shared.applyPreset(settings)
            withAnimation(.easeOut(duration: 0.2)) { activePresetName = name }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { if activePresetName == name { activePresetName = "" } }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: activePresetName == name ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 9))
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(activePresetName == name ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
            )
            .foregroundStyle(activePresetName == name ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func droppedFileCategories() -> Set<FileCategory> {
        var categories = Set<FileCategory>()
        let detector = FileTypeDetector()
        for file in droppedFiles {
            if let detected = try? detector.detect(url: file.url) {
                categories.insert(detected.category)
            }
        }
        return categories
    }

    private func presetMatchesCategories(_ preset: PresetSettings, _ categories: Set<FileCategory>) -> Bool {
        let hasImageSettings = preset.jpegQuality != nil || preset.resizePercent != nil || preset.stripMetadata != nil
        let hasVideoSettings = preset.videoPreset != nil
        let hasAudioSettings = preset.audioBitrate != nil

        // Pure image preset (no video/audio fields)
        if hasImageSettings && !hasVideoSettings && !hasAudioSettings && categories.contains(.image) { return true }
        // Pure video preset (no image fields)
        if hasVideoSettings && !hasImageSettings && !hasAudioSettings && categories.contains(.video) { return true }
        // Pure audio preset
        if hasAudioSettings && !hasImageSettings && !hasVideoSettings && categories.contains(.audio) { return true }
        // Video also shows for audio extraction
        if hasVideoSettings && categories.contains(.video) { return true }
        if hasAudioSettings && categories.contains(.audio) { return true }
        return false
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Files"
        panel.message = "Select files or folders to convert"
        if panel.runModal() == .OK {
            let newFiles = panel.urls.map { DroppedFile(url: $0) }
            withAnimation(.easeOut(duration: 0.15)) {
                convertedResults.removeAll()
                droppedFiles.append(contentsOf: newFiles)
            }
            refreshAvailableFormats()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var newURLs: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                if let data = item as? Data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString) {
                    DispatchQueue.main.async { newURLs.append(url) }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let newFiles = newURLs.map { DroppedFile(url: $0) }
            withAnimation(.easeOut(duration: 0.15)) {
                convertedResults.removeAll()
                droppedFiles.append(contentsOf: newFiles)
            }
            refreshAvailableFormats()
        }
        return true
    }

    private func convertFiles() {
        guard !droppedFiles.isEmpty else { return }

        var renameMap: [URL: String] = [:]
        for file in droppedFiles {
            let originalBase = file.url.deletingPathExtension().lastPathComponent
            if file.outputName != originalBase && !file.outputName.isEmpty {
                renameMap[file.url] = file.outputName
            }
        }

        // Group files by their target format (per-file override or global)
        var byFormat: [String: [URL]] = [:]
        for file in droppedFiles {
            let fmt = file.formatOverride ?? selectedFormatId
            byFormat[fmt, default: []].append(file.url)
        }

        // Convert each group
        for (formatId, urls) in byFormat {
            appDelegate.runConversion(for: urls, targetFormatId: formatId, renameMap: renameMap)
        }

        withAnimation(.easeOut(duration: 0.15)) {
            droppedFiles.removeAll()
            availableFormats = OutputFormat.allCases.map { $0 }
        }
    }

    private func refreshAvailableFormats() {
        let urls = droppedFiles.map { $0.url }
        if urls.isEmpty {
            availableFormats = OutputFormat.allCases.map { $0 }
            return
        }
        let service = QuickActionConversionService()
        if let outputs = try? service.availableOutputs(for: urls), !outputs.isEmpty {
            availableFormats = outputs
            if !outputs.contains(where: { $0.rawValue == selectedFormatId }) {
                selectedFormatId = outputs.first?.rawValue ?? OutputFormat.jpeg.rawValue
            }
        }
    }
}

// MARK: - Formats

struct FormatsTab: View {
    @State private var enabledFormats: [OutputFormat] = PreferencesManager.shared.enabledFormats

    private let categories: [(title: String, icon: String, formats: [OutputFormat])] = [
        ("Images", "photo", OutputFormat.allCases.filter { $0.category == .image }),
        ("Video", "film", OutputFormat.allCases.filter { $0.category == .video }),
        ("Audio", "waveform", OutputFormat.allCases.filter { $0.category == .audio }),
        ("Documents", "doc.text", OutputFormat.allCases.filter { $0.category == .document }),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Right-Click Menu")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 4)

                Text("Choose which formats appear when you right-click a file in Finder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)

                ForEach(categories, id: \.title) { category in
                    formatSection(title: category.title, icon: category.icon, formats: category.formats)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func formatSection(title: String, icon: String, formats: [OutputFormat]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title.uppercased())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 10)

            // Format rows
            VStack(spacing: 0) {
                ForEach(formats, id: \.self) { format in
                    formatRow(format: format)
                    if format != formats.last {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func formatRow(format: OutputFormat) -> some View {
        FormatRowView(format: format, enabledFormats: $enabledFormats)
    }
}

struct FormatRowView: View {
    let format: OutputFormat
    @Binding var enabledFormats: [OutputFormat]
    @State private var showSettings = false
    @State private var quality: Double
    @State private var resizePercent: Int
    @State private var videoPreset: String
    @State private var audioSampleRate: Int
    @State private var audioBitrate: Int
    @State private var stripMetadata: Bool

    private var hasSettings: Bool {
        format.supportsQuality || format.supportsResize || format.supportsVideoQuality || format.supportsAudioSampleRate || format.supportsAudioBitrate || format.category == .image
    }

    init(format: OutputFormat, enabledFormats: Binding<[OutputFormat]>) {
        self.format = format
        self._enabledFormats = enabledFormats
        self._quality = State(initialValue: PreferencesManager.shared.quality(for: format))
        self._resizePercent = State(initialValue: PreferencesManager.shared.resizePercent(for: format))
        self._videoPreset = State(initialValue: PreferencesManager.shared.videoPreset(for: format))
        self._audioSampleRate = State(initialValue: PreferencesManager.shared.audioSampleRate(for: format))
        self._audioBitrate = State(initialValue: PreferencesManager.shared.audioBitrate(for: format))
        self._stripMetadata = State(initialValue: PreferencesManager.shared.stripMetadata(for: format))
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("." + format.preferredExtension)
                .font(.system(.body, design: .monospaced, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 60, alignment: .leading)

            Text(format.displayName)
                .font(.body)
                .foregroundStyle(.secondary)

            // Show current settings summary
            if hasSettings {
                let parts = settingsSummary
                if !parts.isEmpty {
                    Text(parts)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 6)
                }
            }

            Spacer()

            if hasSettings {
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                        .foregroundStyle(showSettings ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings, arrowEdge: .leading) {
                    formatSettingsPopover
                }
                .padding(.trailing, 10)
            }

            Toggle("", isOn: Binding(
                get: { enabledFormats.contains(format) },
                set: { isEnabled in
                    withAnimation(.easeOut(duration: 0.15)) {
                        if isEnabled {
                            enabledFormats.append(format)
                        } else {
                            enabledFormats.removeAll { $0 == format }
                        }
                    }
                    PreferencesManager.shared.enabledFormats = enabledFormats
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var settingsSummary: String {
        var parts: [String] = []
        if format.supportsQuality && quality < 0.95 {
            parts.append("\(Int(quality * 100))%q")
        }
        if format.supportsResize && resizePercent < 100 {
            parts.append("\(resizePercent)%sz")
        }
        if format.supportsVideoQuality && videoPreset != "highest" {
            parts.append(videoPreset)
        }
        if format.supportsAudioSampleRate && audioSampleRate != 44100 {
            parts.append("\(audioSampleRate / 1000)kHz")
        }
        if format.supportsAudioBitrate && audioBitrate != 128000 {
            parts.append("\(audioBitrate / 1000)k")
        }
        if format.category == .image && stripMetadata {
            parts.append("strip")
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private var formatSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(format.displayName) Settings")
                .font(.headline)

            if format.supportsQuality {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Quality")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(quality * 100))%")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $quality, in: 0.1...1.0, step: 0.05)
                        .onChange(of: quality) { _, val in
                            PreferencesManager.shared.setQuality(val, for: format)
                        }
                    HStack {
                        Text("Smaller file")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Best quality")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if format.supportsResize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resize on convert")
                        .font(.subheadline)
                    Picker("", selection: $resizePercent) {
                        Text("100%").tag(100)
                        Text("75%").tag(75)
                        Text("50%").tag(50)
                        Text("25%").tag(25)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: resizePercent) { _, val in
                        PreferencesManager.shared.setResizePercent(val, for: format)
                    }
                }
            }

            if format.supportsVideoQuality {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export quality")
                        .font(.subheadline)
                    Picker("", selection: $videoPreset) {
                        Text("Highest").tag("highest")
                        Text("High").tag("high")
                        Text("Medium").tag("medium")
                        Text("Low").tag("low")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: videoPreset) { _, val in
                        PreferencesManager.shared.setVideoPreset(val, for: format)
                    }
                }
            }

            if format.supportsAudioBitrate {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Bitrate")
                            .font(.subheadline)
                        Spacer()
                        Text("\(audioBitrate / 1000) kbps")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Picker("", selection: $audioBitrate) {
                        Text("64").tag(64000)
                        Text("128").tag(128000)
                        Text("192").tag(192000)
                        Text("256").tag(256000)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: audioBitrate) { _, val in
                        PreferencesManager.shared.setAudioBitrate(val, for: format)
                    }
                }
            }

            if format.supportsAudioSampleRate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample rate")
                        .font(.subheadline)
                    Picker("", selection: $audioSampleRate) {
                        Text("22.05 kHz").tag(22050)
                        Text("44.1 kHz").tag(44100)
                        Text("48 kHz").tag(48000)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: audioSampleRate) { _, val in
                        PreferencesManager.shared.setAudioSampleRate(val, for: format)
                    }
                }
            }

            if format.category == .image {
                Toggle("Strip metadata (EXIF/GPS)", isOn: $stripMetadata)
                    .font(.subheadline)
                    .onChange(of: stripMetadata) { _, val in
                        PreferencesManager.shared.setStripMetadata(val, for: format)
                    }
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}


// MARK: - History

struct HistoryTab: View {
    @ObservedObject var appDelegate: AppDelegate
    @State private var entries: [ConversionHistoryEntry] = ConversionHistoryStore.shared.entries
    @State private var undoneEntries: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History")
                    .font(.title2.weight(.bold))
                Spacer()
                if !entries.isEmpty {
                    Button("Clear") {
                        ConversionHistoryStore.shared.clear()
                        withAnimation { entries = [] }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 16)

            if entries.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(.quaternary)
                    Text("No conversions yet")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Convert files from Finder or drag them here.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(entries) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .onChange(of: appDelegate.historyRefreshTrigger) { _, _ in
            entries = ConversionHistoryStore.shared.entries
        }
    }

    private func historyRow(_ entry: ConversionHistoryEntry) -> some View {
        Button {
            // Click to reveal output in Finder
            if let path = entry.outputFiles.first, path.hasPrefix("/") {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    // File was deleted/moved — reveal parent folder
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                }
            }
        } label: {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: iconForAction(entry.action))
                    .font(.system(size: 16))
                    .foregroundStyle(entry.success ? Color.accentColor : .red)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(entry.success ? Color.accentColor.opacity(0.1) : Color.red.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(titleForEntry(entry))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(entry.outputFormat)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))

                        Text(formatSize(entry.totalOutputSize))
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if !entry.success, let err = entry.errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                if undoneEntries.contains(entry.id) {
                    Text("Undone")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if entry.success && entry.outputFiles.contains(where: { $0.hasPrefix("/") }) {
                    Button {
                        undoEntry(entry)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Move output files to Trash")
                }

                Text(relativeTime(entry.date))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func undoEntry(_ entry: ConversionHistoryEntry) {
        for path in entry.outputFiles {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        withAnimation { undoneEntries.insert(entry.id) }
    }

    private func iconForAction(_ action: String) -> String {
        switch action {
        case "merge": return "doc.on.doc"
        case "split": return "scissors"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private func titleForEntry(_ entry: ConversionHistoryEntry) -> String {
        let inputs = entry.inputFiles.prefix(2).joined(separator: ", ")
        let extra = entry.inputFiles.count > 2 ? " +\(entry.inputFiles.count - 2)" : ""
        return inputs + extra
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = -date.timeIntervalSinceNow
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Settings

struct SettingsTab: View {
    @State private var renameSuffix: String = PreferencesManager.shared.renameSuffix
    @State private var useCustomOutput = PreferencesManager.shared.useCustomOutputFolder
    @State private var customOutputPath: String = PreferencesManager.shared.customOutputFolder?.path ?? ""
    @State private var showNotifications = true
    @State private var activePreset: String = ""
    @State private var showCreatePreset = false
    @State private var newPresetName = ""
    @State private var newPresetJpegQ: Double = 0.9
    @State private var newPresetResize: Int = 100
    @State private var newPresetStrip = false
    @State private var newPresetVideo = "highest"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                // --- Output ---
                settingsSection(title: "OUTPUT", icon: "folder") {
                    // Default suffix
                    settingsRow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Default output suffix")
                                .font(.body)
                            Text("Added to filenames when converting from Finder. Leave empty for no suffix.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        TextField("suffix", text: $renameSuffix)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 150)
                            .onChange(of: renameSuffix) { _, val in
                                PreferencesManager.shared.renameSuffix = val
                            }
                    }
                    Divider().padding(.leading, 16)

                    // Custom output folder
                    settingsRow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom output folder")
                                .font(.body)
                            if useCustomOutput && !customOutputPath.isEmpty {
                                Text(customOutputPath)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            } else {
                                Text("Files are saved beside the original by default.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if useCustomOutput {
                            Button("Change") { pickOutputFolder() }
                                .font(.caption)
                                .padding(.trailing, 8)
                        }
                        Toggle("", isOn: $useCustomOutput)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .onChange(of: useCustomOutput) { _, val in
                                PreferencesManager.shared.useCustomOutputFolder = val
                                if val && customOutputPath.isEmpty { pickOutputFolder() }
                            }
                    }
                }

                // --- Presets ---
                settingsSection(title: "PRESETS", icon: "slider.horizontal.2.square") {
                    // Built-in presets
                    ForEach(PresetSettings.builtIn.indices, id: \.self) { i in
                        if i > 0 { Divider().padding(.leading, 52) }
                        presetRow(name: PresetSettings.builtIn[i].name, icon: PresetSettings.builtIn[i].icon, settings: PresetSettings.builtIn[i].settings)
                    }

                    // User presets
                    let userPresets = PreferencesManager.shared.loadAllPresets()
                    if !userPresets.isEmpty {
                        Divider().padding(.vertical, 4)
                        HStack {
                            Text("MY PRESETS")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)

                        ForEach(Array(userPresets.keys.sorted()), id: \.self) { name in
                            Divider().padding(.leading, 16)
                            settingsRow {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                Text(name)
                                    .font(.body)
                                Spacer()
                                Button("Apply") {
                                    if let p = PreferencesManager.shared.loadPreset(name: name) {
                                        PreferencesManager.shared.applyPreset(p)
                                        activePreset = name
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { activePreset = "" }
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Button {
                                    PreferencesManager.shared.deletePreset(name: name)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Create new preset
                    Divider().padding(.vertical, 4)
                    settingsRow {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22)
                        Text("Create New Preset")
                            .font(.body.weight(.medium))
                        Spacer()
                        Button("Create") { showCreatePreset = true }
                            .font(.caption)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }

                // --- Notifications ---
                settingsSection(title: "NOTIFICATIONS", icon: "bell") {
                    settingsRow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Show notifications")
                                .font(.body)
                            Text("Display start/finish notifications for large file conversions (>1 MB).")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $showNotifications)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                }

                // --- Finder Extension ---
                settingsSection(title: "FINDER EXTENSION", icon: "puzzlepiece.extension") {
                    settingsRow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Enable Finder Extension")
                                .font(.body)
                            Text("Opens System Settings to enable the right-click menu integration.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // --- Keyboard Shortcuts ---
                settingsSection(title: "KEYBOARD SHORTCUTS", icon: "keyboard") {
                    shortcutRow("Switch to Converter", "Cmd + 1")
                    Divider().padding(.leading, 16)
                    shortcutRow("Switch to Formats", "Cmd + 2")
                    Divider().padding(.leading, 16)
                    shortcutRow("Switch to History", "Cmd + 3")
                    Divider().padding(.leading, 16)
                    shortcutRow("Switch to Settings", "Cmd + 4")
                    Divider().padding(.leading, 16)
                    shortcutRow("Open Docs", "Cmd + 5")
                    Divider().padding(.leading, 16)
                    shortcutRow("Open Settings", "Cmd + ,")
                    Divider().padding(.leading, 16)
                    shortcutRow("Open Help / Docs", "Cmd + ?")
                }

                // --- About ---
                settingsSection(title: "ABOUT", icon: "info.circle") {
                    settingsRow {
                        Text("Version")
                            .font(.body)
                        Spacer()
                        Text("1.0.0")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Divider().padding(.leading, 16)
                    settingsRow {
                        Text("macOS Requirement")
                            .font(.body)
                        Spacer()
                        Text("14.0+")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Divider().padding(.leading, 16)
                    settingsRow {
                        Text("Bundled Libraries")
                            .font(.body)
                        Spacer()
                        Text("LAME 3.100, libwebp 1.3.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showCreatePreset) {
            CreatePresetSheet(isPresented: $showCreatePreset)
        }
    }

    private func presetRow(name: String, icon: String, settings: PresetSettings) -> some View {
        settingsRow {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                if let desc = settings.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Apply") {
                PreferencesManager.shared.applyPreset(settings)
                activePreset = name
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { activePreset = "" }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
            if activePreset == name {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    // MARK: - Components

    private func settingsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 10)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> some View {
        settingsRow {
            Text(action)
                .font(.body)
            Spacer()
            Text(shortcut)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .foregroundStyle(.secondary)
        }
    }

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            customOutputPath = url.path
            PreferencesManager.shared.customOutputFolder = url
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            Group {
                switch currentPage {
                case 0: welcomePage
                case 1: permissionsPage
                case 2: finderExtensionPage
                case 3: howToUsePage
                default: readyPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation { currentPage -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Dots
                HStack(spacing: 6) {
                    ForEach(0..<5) { i in
                        Circle()
                            .fill(i == currentPage ? Color.accentColor : Color.primary.opacity(0.15))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                if currentPage < 4 {
                    Button("Next") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("Welcome to FinderConvert")
                .font(.title.weight(.bold))

            Text("Convert any file directly from Finder.\nImages, videos, audio, documents, and more.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
        }
        .padding(32)
    }

    private var permissionsPage: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Permissions")
                .font(.title2.weight(.bold))

            Text("FinderConvert needs a couple of permissions to work properly.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    icon: "bell.badge",
                    color: .orange,
                    title: "Notifications",
                    description: "Get notified when conversions start and finish.",
                    action: {
                        Task {
                            let center = UNUserNotificationCenter.current()
                            try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                        }
                    },
                    buttonText: "Enable"
                )

                permissionRow(
                    icon: "folder",
                    color: .blue,
                    title: "Full Disk Access",
                    description: "Allows converting files anywhere on your Mac.",
                    action: {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    },
                    buttonText: "Open Settings"
                )

                permissionRow(
                    icon: "puzzlepiece.extension",
                    color: .green,
                    title: "Finder Extension",
                    description: "Adds right-click conversion to Finder.",
                    action: {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                    },
                    buttonText: "Enable"
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .padding(.horizontal, 16)

            Spacer()
        }
        .padding(32)
    }

    private var finderExtensionPage: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "cursorarrow.click.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Enable Finder Extension")
                .font(.title2.weight(.bold))

            Text("This is the most important step. Enable the extension so you can right-click files to convert them.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                instructionStep(1, "Open the button below to go to System Settings")
                instructionStep(2, "Find **FinderConvert** in the list")
                instructionStep(3, "Toggle it **on**")
            }
            .padding(.horizontal, 16)

            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
            } label: {
                Label("Open Finder Extension Settings", systemImage: "gear")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(32)
    }

    private var howToUsePage: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "hand.point.up.left")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("How to Use")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 16) {
                usageRow(
                    icon: "cursorarrow.click",
                    title: "Right-Click in Finder",
                    description: "Select any file, right-click, choose Convert File and pick your format."
                )
                usageRow(
                    icon: "arrow.down.doc",
                    title: "Drag & Drop",
                    description: "Drop files onto the menu bar icon or the app window to convert."
                )
                usageRow(
                    icon: "folder",
                    title: "Convert Folders",
                    description: "Right-click a folder to convert all files inside, preserving structure."
                )
                usageRow(
                    icon: "doc.on.doc",
                    title: "PDF Tools",
                    description: "Select multiple PDFs to merge, or one PDF to split into pages."
                )
            }
            .padding(16)

            Spacer()
        }
        .padding(32)
    }

    private var readyPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title.weight(.bold))

            Text("FinderConvert lives in your menu bar.\nRight-click any file in Finder to start converting.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            HStack(spacing: 24) {
                featureBadge(icon: "photo", label: "Images")
                featureBadge(icon: "film", label: "Video")
                featureBadge(icon: "waveform", label: "Audio")
                featureBadge(icon: "doc.text", label: "Docs")
                featureBadge(icon: "tablecells", label: "Data")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Components

    private func permissionRow(icon: String, color: Color, title: String, description: String, action: (() -> Void)?, buttonText: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let action, let text = buttonText {
                Button(text) { action() }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
    }

    private func instructionStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func usageRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func featureBadge(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Create Preset Sheet

struct CreatePresetSheet: View {
    @Binding var isPresented: Bool

    enum PresetType: String, CaseIterable {
        case image = "Image"
        case video = "Video"
        case audio = "Audio"
    }

    @State private var name = ""
    @State private var selectedType: PresetType = .image

    // Image settings
    @State private var quality: Double = 0.9
    @State private var resize: Int = 100
    @State private var stripMeta = false

    // Video settings
    @State private var videoPreset = "highest"

    // Audio settings
    @State private var audioBitrate: Int = 128000
    @State private var sampleRate: Int = 44100

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Preset").font(.title3.weight(.bold))

            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Type picker
            Picker("Type", selection: $selectedType) {
                ForEach(PresetType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: iconFor(type)).tag(type)
                }
            }
            .pickerStyle(.segmented)

            // Settings based on type
            switch selectedType {
            case .image:
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Quality")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(quality * 100))%")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $quality, in: 0.1...1.0, step: 0.05)
                        HStack {
                            Text("Smaller").font(.caption2).foregroundStyle(.tertiary)
                            Spacer()
                            Text("Best").font(.caption2).foregroundStyle(.tertiary)
                        }

                        Divider()

                        Text("Resize").font(.subheadline)
                        Picker("", selection: $resize) {
                            Text("100%").tag(100)
                            Text("75%").tag(75)
                            Text("50%").tag(50)
                            Text("25%").tag(25)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Divider()

                        Toggle("Strip metadata (EXIF / GPS)", isOn: $stripMeta)
                            .font(.subheadline)
                    }
                    .padding(4)
                } label: {
                    Label("Image Settings", systemImage: "photo")
                }

            case .video:
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Export quality").font(.subheadline)
                        Picker("", selection: $videoPreset) {
                            Text("Highest").tag("highest")
                            Text("High").tag("high")
                            Text("Medium").tag("medium")
                            Text("Low").tag("low")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(4)
                } label: {
                    Label("Video Settings", systemImage: "film")
                }

            case .audio:
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Bitrate").font(.subheadline)
                        Picker("", selection: $audioBitrate) {
                            Text("64 kbps").tag(64000)
                            Text("128 kbps").tag(128000)
                            Text("192 kbps").tag(192000)
                            Text("256 kbps").tag(256000)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Divider()

                        Text("Sample rate").font(.subheadline)
                        Picker("", selection: $sampleRate) {
                            Text("22.05 kHz").tag(22050)
                            Text("44.1 kHz").tag(44100)
                            Text("48 kHz").tag(48000)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(4)
                } label: {
                    Label("Audio Settings", systemImage: "waveform")
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Create") {
                    guard !name.isEmpty else { return }
                    let preset = PresetSettings(
                        jpegQuality: selectedType == .image ? quality : nil,
                        heicQuality: selectedType == .image ? quality : nil,
                        webpQuality: selectedType == .image ? quality : nil,
                        avifQuality: selectedType == .image ? quality : nil,
                        resizePercent: selectedType == .image ? resize : nil,
                        videoPreset: selectedType == .video ? videoPreset : nil,
                        stripMetadata: selectedType == .image ? stripMeta : nil,
                        audioBitrate: selectedType == .audio ? audioBitrate : nil
                    )
                    PreferencesManager.shared.savePreset(name: name, settings: preset)
                    name = ""
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func iconFor(_ type: PresetType) -> String {
        switch type {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }
}

// MARK: - Docs

struct DocsTab: View {
    @State private var selectedSection: DocSection = .gettingStarted

    enum DocSection: String, CaseIterable, Identifiable {
        case gettingStarted = "Getting Started"
        case finderMenu = "Finder Menu"
        case imageConversion = "Images"
        case videoAudio = "Video & Audio"
        case documents = "Documents"
        case spreadsheets = "Spreadsheets"
        case folders = "Folders"
        case pdfTools = "PDF Tools"
        case settings = "Settings"
        case tips = "Tips & Tricks"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .gettingStarted: return "star"
            case .finderMenu: return "cursorarrow.click"
            case .imageConversion: return "photo"
            case .videoAudio: return "film"
            case .documents: return "doc.text"
            case .spreadsheets: return "tablecells"
            case .folders: return "folder"
            case .pdfTools: return "doc.on.doc"
            case .settings: return "slider.horizontal.3"
            case .tips: return "lightbulb"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Topic list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(DocSection.allCases) { section in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { selectedSection = section }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(selectedSection == section ? Color.accentColor : .secondary)
                                    .frame(width: 18)
                                Text(section.rawValue)
                                    .font(.subheadline)
                                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selectedSection == section ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .frame(width: 160)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Content
            ScrollView {
                docContent(for: selectedSection)
                    .padding(24)
                    .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder
    private func docContent(for section: DocSection) -> some View {
        switch section {
        case .gettingStarted:
            docCard {
                VStack(alignment: .leading, spacing: 16) {
                    docHeading("Quick Start")
                    docStep(1, "Enable the Finder Extension",
                            "Go to **System Settings > Privacy & Security > Extensions > Finder Extensions** and toggle on **FinderConvert**.")
                    docStep(2, "Right-Click Any File",
                            "Select one or more files in Finder, right-click, and look for **Convert File** in the context menu.")
                    docStep(3, "Choose Your Format",
                            "Pick the target format from the submenu. The converted file appears beside the original.")
                    docStep(4, "Or Drag & Drop",
                            "Open FinderConvert, drag files onto the **Converter** tab, choose a format, and click **Convert**.")
                    docNote("The app stays running in the background to handle conversions from Finder. You don't need to keep the window open.")
                }
            }

        case .finderMenu:
            docCard {
                VStack(alignment: .leading, spacing: 16) {
                    docHeading("Finder Right-Click Menu")
                    docText("When you right-click files in Finder, FinderConvert shows context-aware options:")
                    docBullet("**Convert File** -- for a single file, shows all compatible output formats")
                    docBullet("**Convert 3 Files** -- for multiple files, shows formats common to all")
                    docBullet("**Convert Folder** -- for a folder, converts all files inside recursively")
                    docBullet("**Merge PDFs** -- appears when 2+ PDF files are selected")
                    docBullet("**Split PDF** -- appears when a single PDF is selected")
                    docNote("Only formats that are actually supported for your selection appear. A .mov file won't show image formats unless you also select images.")
                }
            }

        case .imageConversion:
            docCard {
                VStack(alignment: .leading, spacing: 16) {
                    docHeading("Image Conversion")
                    docText("Supported inputs: **JPEG, PNG, HEIC, TIFF, GIF, WebP, BMP, SVG, AVIF**")
                    docText("Supported outputs: **JPEG, PNG, HEIC, TIFF, GIF, BMP, ICO, AVIF, WebP**")

                    Divider()
                    docSubheading("Per-Format Settings")
                    docBullet("**Quality** -- JPEG, HEIC, AVIF, WebP have a quality slider (10-100%)")
                    docBullet("**Resize** -- All image formats can resize to 75%, 50%, or 25%")
                    docBullet("**Strip Metadata** -- Remove EXIF/GPS data from output")

                    Divider()
                    docSubheading("Special Conversions")
                    docBullet("**SVG to raster** -- Renders vector at 1024px+ resolution")
                    docBullet("**Any image to ICO** -- Auto-resizes to 256x256 for favicons")
                    docBullet("**PDF to images** -- Multi-page PDFs create one image per page in a folder")
                }
            }

        case .videoAudio:
            docCard {
                VStack(alignment: .leading, spacing: 16) {
                    docHeading("Video & Audio")
                    docText("**Video inputs:** MP4, MOV, WebM")
                    docText("**Video outputs:** MP4, MOV, HEVC")
                    docText("**Audio inputs:** MP3, M4A, WAV, AIFF, FLAC, OGG")
                    docText("**Audio outputs:** MP3, M4A, WAV, AIFF, FLAC")

                    Divider()
                    docSubheading("Extract Audio from Video")
                    docText("Right-click any video file and choose M4A, MP3, WAV, AIFF, or FLAC to extract just the audio track.")
                    docNote("The video must have an audio track. Screen recordings without a microphone won't have audio to extract.")

                    Divider()
                    docSubheading("Video to GIF")
                    docText("Convert any video to an animated GIF. The output is capped at 480px wide and 200 frames (10fps).")

                    Divider()
                    docSubheading("Settings")
                    docBullet("**Video quality** -- Highest, High, Medium, Low presets")
                    docBullet("**Audio bitrate** -- 64, 128, 192, 256 kbps (MP3, M4A)")
                    docBullet("**Sample rate** -- 22.05, 44.1, 48 kHz")
                }
            }

        case .documents:
            docCard {
                VStack(alignment: .leading, spacing: 16) {
                    docHeading("Document Conversion")
                    docText("**Inputs:** PDF, RTF, HTML, TXT, Markdown (.md), DOCX, EPUB")
                    docText("**Outputs:** PDF, RTF, HTML, TXT, DOCX")

                    Divider()
                    docSubheading("Markdown")
                    docText("Renders headings, **bold**, *italic*, `code`, lists, blockquotes, and links. HTML output includes clean CSS styling.")

                    Divider()
                    docSubheading("EPUB")
                    docText("Parses chapter order from the EPUB spine. Outputs as PDF (via WebKit rendering), HTML, or plain text.")

                    Divider()
                    docSubheading("DOCX Output")
                    docText("Creates valid Word documents from TXT, RTF, HTML, or Markdown. Preserves bold and italic formatting.")
                }
            }

        case .spreadsheets:
            docCard {
                VStack(alignment: .leading, spacing: 16) {
                    docHeading("Spreadsheets & Data")
                    docText("**Inputs:** CSV, TSV, XLSX, JSON")
                    docText("**Outputs:** CSV, TSV, XLSX")

                    Divider()
                    docSubheading("Multi-Sheet XLSX")
                    docText("When converting an XLSX with multiple sheets to CSV/TSV, each sheet becomes a separate file inside a folder named after the original file.")
                    docBullet("Single sheet: one flat CSV file")
                    docBullet("Multiple sheets: folder with one CSV per sheet, named after the sheet")

                    Divider()
                    docSubheading("JSON to CSV")
                    docText("Flattens arrays of JSON objects into rows. Object keys become column headers. Nested objects are serialized as JSON strings in cells.")
                }
            }

        case .folders:
            docCard {
                VStack(alignment: .leading, spacing: 16) {
                    docHeading("Folder Conversion")
                    docText("Right-click any folder and choose a format. FinderConvert will:")
                    docBullet("Recursively find all convertible files inside the folder")
                    docBullet("Create a **\"folder converted\"** directory beside the original")
                    docBullet("Mirror the entire directory structure with converted files")
                    docBullet("Skip files that don't support the chosen output format")
                    docNote("Hidden files (starting with .) are skipped. The original folder is never modified.")
                }
            }

        case .pdfTools:
            docCard {
                VStack(alignment: .leading, spacing: 16) {
                    docHeading("PDF Tools")

                    docSubheading("Merge PDFs")
                    docText("Select 2 or more PDF files in Finder, right-click, and choose **Merge PDFs**. Pages are combined in selection order.")

                    Divider()
                    docSubheading("Split PDF")
                    docText("Right-click a single PDF and choose **Split PDF**. Creates a folder with one PDF per page, zero-padded for sorting (Page 01, Page 02...).")

                    Divider()
                    docSubheading("PDF to Images")
                    docText("Convert a PDF to JPEG, PNG, HEIC, or TIFF. Multi-page PDFs produce one image per page in a folder. Single-page PDFs produce a single image file.")
                }
            }

        case .settings:
            docCard {
                VStack(alignment: .leading, spacing: 16) {
                    docHeading("Settings & Customization")

                    docSubheading("Per-Format Quality")
                    docText("Click the slider icon next to any format in the **Formats** tab to adjust quality, resize, bitrate, or sample rate for that specific format.")

                    Divider()
                    docSubheading("Output Suffix")
                    docText("Change the default \" converted\" suffix in the **Converter** tab. Set it to empty for no suffix (uses collision numbering instead).")

                    Divider()
                    docSubheading("Custom Output Folder")
                    docText("Toggle the switch in the **Converter** tab and choose a folder. All conversions will output there instead of beside the source file.")

                    Divider()
                    docSubheading("Preset Profiles")
                    docText("Save your current quality/resize/video settings as a named preset from the **Presets** menu. Apply presets instantly before converting.")

                    Divider()
                    docSubheading("Metadata Stripping")
                    docText("Enable per-format in the format settings popover. Removes EXIF, GPS, camera info, and other metadata from images.")
                }
            }

        case .tips:
            docCard {
                VStack(alignment: .leading, spacing: 16) {
                    docHeading("Tips & Tricks")
                    docBullet("**Batch convert** -- Select multiple files of different types. The menu shows formats compatible with all of them.")
                    docBullet("**Quick favicon** -- Right-click any image > ICO. Auto-resizes to 256x256.")
                    docBullet("**Web-ready images** -- Set JPEG quality to 70% and resize to 50% for fast-loading web images.")
                    docBullet("**Extract podcast audio** -- Right-click a video > MP3 to get just the audio.")
                    docBullet("**Convert clipboard** -- Drag & drop from other apps directly into the Converter tab.")
                    docBullet("**XLSX to clean CSV** -- Multi-sheet spreadsheets automatically split into separate, properly named CSV files.")
                    docBullet("**Undo mistakes** -- Go to the **History** tab and click the trash icon to move any conversion output to Trash.")

                    Divider()
                    docSubheading("Keyboard Shortcuts")
                    docBullet("**Cmd+1/2/3/4/5** -- Switch between sidebar tabs")
                    docBullet("**Cmd+Q** -- Quit (app stays in background for Finder conversions)")
                }
            }
        }
    }

    // MARK: - Doc Components

    private func docCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05))
            )
    }

    private func docHeading(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
    }

    private func docSubheading(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private func docText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func docBullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func docStep(_ number: Int, _ title: String, _ description: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func docNote(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
                .font(.subheadline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.blue.opacity(0.06))
        )
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("FinderConvert")
                .font(.title.weight(.bold))

            Text("1.0.0")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.top, -14)

            Text("A native macOS utility for converting files\ndirectly from Finder's right-click menu.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer()

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    instructionRow(step: "1", text: "Right-click any file in Finder")
                    instructionRow(step: "2", text: "Choose **Convert File** from the menu")
                    instructionRow(step: "3", text: "Pick your target format")
                }
                .padding(4)
            } label: {
                Label("How to use", systemImage: "questionmark.circle")
            }
            .frame(maxWidth: 340)

            Spacer()
        }
        .padding(32)
    }

    private func instructionRow(step: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
