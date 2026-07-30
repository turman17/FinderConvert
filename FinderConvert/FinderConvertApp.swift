import SwiftUI
import UserNotifications
import FinderConvertCore
import OSLog
import AppKit
import Combine

extension Notification.Name {
    static let navigateToTab = Notification.Name("FinderConvert.navigateToTab")
    static let showTipsPopover = Notification.Name("FinderConvert.showTipsPopover")
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

        // Tips menu
        let tipsMenu = NSMenu(title: "Tips")
        tipsMenu.addItem(withTitle: "Tips & Tricks", action: #selector(showTips), keyEquivalent: "?")
        tipsMenu.addItem(NSMenuItem.separator())
        tipsMenu.addItem(withTitle: "Show Tips Button", action: #selector(toggleTipsButton), keyEquivalent: "")
        let tipsMenuItem = NSMenuItem()
        tipsMenuItem.submenu = tipsMenu
        mainMenu.addItem(tipsMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Converter", action: #selector(showConverter), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "Formats", action: #selector(showFormats), keyEquivalent: "2")
        viewMenu.addItem(withTitle: "Presets", action: #selector(showPresets), keyEquivalent: "3")
        viewMenu.addItem(withTitle: "History", action: #selector(showHistory), keyEquivalent: "4")
        viewMenu.addItem(withTitle: "Settings", action: #selector(showSettings), keyEquivalent: "5")
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

    @objc func showPresets() {
        openPreferencesWindow()
        navigateToTab(.presets)
    }

    @objc func showHistory() {
        openPreferencesWindow()
        navigateToTab(.history)
    }

    @objc func showSettings() {
        openPreferencesWindow()
        navigateToTab(.settings)
    }

    @objc func showTips() {
        openPreferencesWindow()
        NotificationCenter.default.post(name: .showTipsPopover, object: nil)
    }

    @objc func toggleTipsButton() {
        let current = UserDefaults.standard.object(forKey: "showTipsCircle") as? Bool ?? true
        UserDefaults.standard.set(!current, forKey: "showTipsCircle")
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleTipsButton) {
            let shown = UserDefaults.standard.object(forKey: "showTipsCircle") as? Bool ?? true
            menuItem.state = shown ? .on : .off
        }
        return true
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

    @discardableResult
    func runConversion(for urls: [URL], targetFormatId: String?, renameMap: [URL: String] = [:], presetName: String? = nil) -> Task<Void, Never> {
        Task {
            // Per-file preset: apply temporarily for this conversion only,
            // restoring the user's settings when it finishes
            var settingsSnapshot: Data?
            if let presetName, let preset = PreferencesManager.shared.presetSettings(named: presetName) {
                settingsSnapshot = PreferencesManager.shared.captureSettingsSnapshotData()
                PreferencesManager.shared.applyPresetValues(preset)
            }
            defer {
                if let settingsSnapshot {
                    PreferencesManager.shared.restoreSettingsSnapshot(settingsSnapshot)
                }
            }
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
    case presets = "Presets"
    case history = "History"
    case settings = "Settings"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .converter: return "arrow.triangle.2.circlepath"
        case .formats: return "checklist"
        case .presets: return "slider.horizontal.2.square"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Main View

struct MainView: View {
    @ObservedObject var appDelegate: AppDelegate
    @State private var selectedItem: SidebarItem = .converter
    @State private var showTips = false
    @AppStorage("showTipsCircle") private var showTipsCircle = true

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
                case .presets:
                    PresetsTab()
                case .history:
                    HistoryTab(appDelegate: appDelegate)
                case .settings:
                    SettingsTab()
                case .about:
                    AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottomTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    // Invisible popover anchor matching the button's frame so
                    // the popover centers on the circle, and tips can still
                    // open from the menu bar when the circle is hidden
                    Color.clear
                        .frame(width: 34, height: 34)
                        .popover(isPresented: $showTips, arrowEdge: .top) {
                            TipsPopover()
                        }

                    if showTipsCircle && selectedItem != .converter {
                        Button {
                            showTips.toggle()
                        } label: {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.accentColor))
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .help("Tips & Tricks — right-click to hide")
                        .contextMenu {
                            Button("Hide Tips Button") { showTipsCircle = false }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { notification in
            if let tab = notification.object as? SidebarItem {
                selectedItem = tab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTipsPopover)) { _ in
            showTips = true
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
    let presetNames: [String]
    let onRename: (String) -> Void
    let onFormatChange: (String?) -> Void
    let onPresetChange: (String?) -> Void
    let onRemove: () -> Void
    @State private var editName: String
    @State private var fileFormat: String
    @State private var filePreset: String?

    init(file: DroppedFile, availableFormats: [OutputFormat] = [], showFormatPicker: Bool = false,
         presetNames: [String] = [],
         onRename: @escaping (String) -> Void, onFormatChange: @escaping (String?) -> Void = { _ in },
         onPresetChange: @escaping (String?) -> Void = { _ in }, onRemove: @escaping () -> Void) {
        self.file = file
        self.availableFormats = availableFormats
        self.showFormatPicker = showFormatPicker
        self.presetNames = presetNames
        self.onRename = onRename
        self.onFormatChange = onFormatChange
        self.onPresetChange = onPresetChange
        self.onRemove = onRemove
        self._editName = State(initialValue: file.outputName)
        self._fileFormat = State(initialValue: file.formatOverride ?? "")
        self._filePreset = State(initialValue: file.presetOverride)
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
            if !presetNames.isEmpty {
                Menu {
                    Button {
                        filePreset = nil
                        onPresetChange(nil)
                    } label: {
                        Text(filePreset == nil ? "✓ Current settings" : "Current settings")
                    }
                    Divider()
                    ForEach(presetNames, id: \.self) { name in
                        Button {
                            filePreset = name
                            onPresetChange(name)
                        } label: {
                            Text(filePreset == name ? "✓ \(name)" : name)
                        }
                    }
                } label: {
                    Image(systemName: filePreset == nil ? "slider.horizontal.3" : "slider.horizontal.2.square")
                        .font(.system(size: 10))
                        .foregroundStyle(filePreset == nil ? Color.secondary : Color.accentColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(filePreset.map { "Preset: \($0)" } ?? "Per-file preset")
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
    var presetOverride: String? // per-file preset (nil = current settings)

    init(url: URL) {
        self.url = url
        self.outputName = url.deletingPathExtension().lastPathComponent
        self.formatOverride = nil
        self.presetOverride = nil
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

    // Which file categories a preset's settings are meaningful for
    private func presetCategories(_ s: PresetSettings) -> Set<FileCategory> {
        var cats = Set<FileCategory>()
        if s.jpegQuality != nil || s.heicQuality != nil || s.webpQuality != nil
            || s.avifQuality != nil || s.resizePercent != nil || s.stripMetadata != nil {
            cats.insert(.image)
        }
        if s.videoPreset != nil { cats.insert(.video) }
        if s.audioBitrate != nil {
            cats.insert(.audio)
            cats.insert(.video) // audio extraction from video
        }
        return cats
    }

    private func fileCategory(_ url: URL) -> FileCategory? {
        (try? FileTypeDetector().detect(url: url))?.category
    }

    private func presetNames(for category: FileCategory?) -> [String] {
        guard let category else { return [] }
        let builtIn = PresetSettings.builtIn
            .filter { presetCategories($0.settings).contains(category) }
            .map(\.name)
        let user = PreferencesManager.shared.loadAllPresets()
            .filter { presetCategories($0.value).contains(category) }
            .keys.sorted()
        return builtIn + user
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 0)
                .onAppear { activePresetName = PreferencesManager.shared.activePresetName ?? "" }
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
                                        presetNames: presetNames(for: fileCategory(file.url)),
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
                                        onPresetChange: { preset in
                                            if let idx = droppedFiles.firstIndex(where: { $0.id == file.id }) {
                                                droppedFiles[idx].presetOverride = preset
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

                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: droppedFiles.isEmpty ? 180 : 260)
            .padding(.horizontal, 32)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
            .animation(.easeInOut(duration: 0.2), value: isTargeted)

            // Global presets strip under the drop zone — all presets when
            // empty, narrowed to the dropped files' categories otherwise
            let droppedCategories = Set(droppedFiles.compactMap { fileCategory($0.url) })
            let visibleBuiltIn = droppedFiles.isEmpty
                ? PresetSettings.builtIn
                : PresetSettings.builtIn.filter { !presetCategories($0.settings).isDisjoint(with: droppedCategories) }
            let visibleUser = droppedFiles.isEmpty
                ? PreferencesManager.shared.loadAllPresets()
                : PreferencesManager.shared.loadAllPresets().filter { !presetCategories($0.value).isDisjoint(with: droppedCategories) }

            if !visibleBuiltIn.isEmpty || !visibleUser.isEmpty {
                HStack(spacing: 10) {
                    Text("Presets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(visibleBuiltIn, id: \.name) { preset in
                                presetPill(name: preset.name, icon: preset.icon, settings: preset.settings)
                            }
                            if !visibleUser.isEmpty {
                                Divider().frame(height: 14)
                                ForEach(Array(visibleUser.keys.sorted()), id: \.self) { name in
                                    if let p = visibleUser[name] {
                                        presetPill(name: name, icon: "slider.horizontal.3", settings: p)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 10)
            }

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
            withAnimation(.easeOut(duration: 0.2)) {
                if activePresetName == name {
                    PreferencesManager.shared.unapplyActivePreset()
                    activePresetName = ""
                } else {
                    let effective = PreferencesManager.shared.presetSettings(named: name) ?? settings
                    PreferencesManager.shared.applyPreset(effective, named: name)
                    activePresetName = name
                }
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

    private struct ConversionGroup: Hashable {
        let formatId: String
        let presetName: String?
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

        // Group files by target format and per-file preset
        var groups: [ConversionGroup: [URL]] = [:]
        for file in droppedFiles {
            let key = ConversionGroup(
                formatId: file.formatOverride ?? selectedFormatId,
                presetName: file.presetOverride
            )
            groups[key, default: []].append(file.url)
        }

        // Run groups sequentially: per-file presets temporarily swap the
        // global settings, so concurrent groups would race
        let delegate = appDelegate
        Task {
            for (group, urls) in groups {
                await delegate.runConversion(
                    for: urls,
                    targetFormatId: group.formatId,
                    renameMap: renameMap,
                    presetName: group.presetName
                ).value
            }
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
    @State private var markdownStyle: MarkdownStyle

    private var supportsMarkdownStyle: Bool {
        format == .pdf || format == .html
    }

    private var hasSettings: Bool {
        format.supportsQuality || format.supportsResize || format.supportsVideoQuality || format.supportsAudioSampleRate || format.supportsAudioBitrate || format.category == .image || supportsMarkdownStyle
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
        self._markdownStyle = State(initialValue: PreferencesManager.shared.markdownStyle)
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
        if supportsMarkdownStyle && markdownStyle != .modern {
            parts.append("md:\(markdownStyle.displayName.lowercased())")
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

            if supportsMarkdownStyle {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Markdown style")
                        .font(.subheadline)
                    Picker("", selection: $markdownStyle) {
                        ForEach(MarkdownStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: markdownStyle) { _, val in
                        PreferencesManager.shared.markdownStyle = val
                    }
                    Text("Used when converting .md files")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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

// MARK: - Settings components (shared by SettingsTab and PresetsTab)

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

// MARK: - Presets

struct PresetsTab: View {
    @State private var activePreset: String?
    @State private var showCreatePreset = false
    @State private var userPresets: [String: PresetSettings] = [:]
    @State private var editingPreset: EditablePreset?
    @State private var overridesVersion = 0

    struct EditablePreset: Identifiable {
        let name: String
        let settings: PresetSettings
        let isBuiltIn: Bool
        var id: String { name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Presets")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Button("New Preset") { showCreatePreset = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 6)

                Text("Applying a preset updates quality, resize, and metadata settings across all matching formats. Unapply restores the settings you had before.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)

                ForEach(PresetSettings.builtInGroups, id: \.title) { group in
                    settingsSection(title: group.title.uppercased(), icon: group.icon) {
                        ForEach(group.presets.indices, id: \.self) { i in
                            if i > 0 { Divider().padding(.leading, 52) }
                            presetRow(name: group.presets[i].name, icon: group.presets[i].icon, settings: group.presets[i].settings)
                        }
                    }
                }

                settingsSection(title: "MY PRESETS", icon: "person") {
                    if userPresets.isEmpty {
                        settingsRow {
                            Text("No custom presets yet. Create one to save your favorite conversion settings.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                    } else {
                        ForEach(Array(userPresets.keys.sorted().enumerated()), id: \.element) { i, name in
                            if i > 0 { Divider().padding(.leading, 52) }
                            settingsRow {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                Text(name)
                                    .font(.body)
                                Spacer()
                                Button {
                                    if let p = PreferencesManager.shared.loadPreset(name: name) {
                                        editingPreset = EditablePreset(name: name, settings: p, isBuiltIn: false)
                                    }
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Edit preset")
                                applyControls(for: name) {
                                    if let p = PreferencesManager.shared.loadPreset(name: name) {
                                        PreferencesManager.shared.applyPreset(p, named: name)
                                        activePreset = name
                                    }
                                }
                                Button {
                                    if activePreset == name {
                                        PreferencesManager.shared.unapplyActivePreset()
                                        activePreset = nil
                                    }
                                    PreferencesManager.shared.deletePreset(name: name)
                                    userPresets = PreferencesManager.shared.loadAllPresets()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .onAppear {
            userPresets = PreferencesManager.shared.loadAllPresets()
            activePreset = PreferencesManager.shared.activePresetName
        }
        .sheet(isPresented: $showCreatePreset) {
            CreatePresetSheet(isPresented: $showCreatePreset)
        }
        .onChange(of: showCreatePreset) { _, isShown in
            if !isShown { userPresets = PreferencesManager.shared.loadAllPresets() }
        }
        .sheet(item: $editingPreset) { preset in
            EditPresetSheet(preset: preset) {
                overridesVersion += 1
                userPresets = PreferencesManager.shared.loadAllPresets()
                // Keep settings in sync if the edited preset is currently applied
                if activePreset == preset.name,
                   let effective = PreferencesManager.shared.presetSettings(named: preset.name) {
                    PreferencesManager.shared.applyPreset(effective, named: preset.name)
                }
            }
        }
        .id(overridesVersion)
    }

    private func presetRow(name: String, icon: String, settings: PresetSettings) -> some View {
        let effective = PreferencesManager.shared.presetSettings(named: name) ?? settings
        let isEdited = PreferencesManager.shared.builtInOverride(named: name) != nil
        return settingsRow {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body)
                    if isEdited {
                        Text("edited")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if let desc = settings.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                editingPreset = EditablePreset(name: name, settings: effective, isBuiltIn: true)
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit preset")
            applyControls(for: name) {
                PreferencesManager.shared.applyPreset(effective, named: name)
                activePreset = name
            }
        }
    }

    @ViewBuilder
    private func applyControls(for name: String, apply: @escaping () -> Void) -> some View {
        if activePreset == name {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            Button("Unapply") {
                PreferencesManager.shared.unapplyActivePreset()
                activePreset = nil
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button("Apply") { apply() }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Settings

struct SettingsTab: View {
    @State private var renameSuffix: String = PreferencesManager.shared.renameSuffix
    @State private var useCustomOutput = PreferencesManager.shared.useCustomOutputFolder
    @State private var customOutputPath: String = PreferencesManager.shared.customOutputFolder?.path ?? ""
    @State private var showNotifications = true
    @AppStorage("showTipsCircle") private var showTipsCircle = true

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

                // --- Tips ---
                settingsSection(title: "TIPS", icon: "lightbulb") {
                    settingsRow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Show tips button")
                                .font(.body)
                            Text("Floating lightbulb in the corner of every tab except Converter. Also available from the Tips menu.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $showTipsCircle)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                }

                // --- Keyboard Shortcuts ---
                settingsSection(title: "KEYBOARD SHORTCUTS", icon: "keyboard") {
                    shortcutRow("Switch to Converter", "Cmd + 1")
                    Divider().padding(.leading, 16)
                    shortcutRow("Switch to Formats", "Cmd + 2")
                    Divider().padding(.leading, 16)
                    shortcutRow("Switch to Presets", "Cmd + 3")
                    Divider().padding(.leading, 16)
                    shortcutRow("Switch to History", "Cmd + 4")
                    Divider().padding(.leading, 16)
                    shortcutRow("Switch to Settings", "Cmd + 5")
                    Divider().padding(.leading, 16)
                    shortcutRow("Open Settings", "Cmd + ,")
                    Divider().padding(.leading, 16)
                    shortcutRow("Tips & Tricks", "Cmd + ?")
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
    }

    // MARK: - Components

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

// MARK: - Edit Preset

struct EditPresetSheet: View {
    let preset: PresetsTab.EditablePreset
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var quality: Double
    @State private var resize: Int
    @State private var stripMeta: Bool
    @State private var videoPreset: String
    @State private var audioBitrate: Int

    private let hasQuality: Bool
    private let hasResize: Bool
    private let hasStrip: Bool
    private let hasVideo: Bool
    private let hasBitrate: Bool

    init(preset: PresetsTab.EditablePreset, onDone: @escaping () -> Void) {
        self.preset = preset
        self.onDone = onDone
        let s = preset.settings
        hasQuality = s.jpegQuality != nil || s.heicQuality != nil || s.webpQuality != nil || s.avifQuality != nil
        hasResize = s.resizePercent != nil
        hasStrip = s.stripMetadata != nil
        hasVideo = s.videoPreset != nil
        hasBitrate = s.audioBitrate != nil
        self._quality = State(initialValue: s.jpegQuality ?? s.heicQuality ?? s.webpQuality ?? s.avifQuality ?? 0.9)
        self._resize = State(initialValue: s.resizePercent ?? 100)
        self._stripMeta = State(initialValue: s.stripMetadata ?? false)
        self._videoPreset = State(initialValue: s.videoPreset ?? "highest")
        self._audioBitrate = State(initialValue: s.audioBitrate ?? 128000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit \(preset.name)").font(.title3.weight(.bold))
            if let desc = preset.settings.description {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if hasQuality {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Image quality").font(.subheadline)
                        Spacer()
                        Text("\(Int(quality * 100))%")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $quality, in: 0.1...1.0, step: 0.05)
                }
            }

            if hasResize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resize").font(.subheadline)
                    Picker("", selection: $resize) {
                        Text("100%").tag(100)
                        Text("75%").tag(75)
                        Text("50%").tag(50)
                        Text("25%").tag(25)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if hasStrip {
                Toggle("Strip metadata (EXIF / GPS)", isOn: $stripMeta)
                    .font(.subheadline)
            }

            if hasVideo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video quality").font(.subheadline)
                    Picker("", selection: $videoPreset) {
                        Text("Highest").tag("highest")
                        Text("High").tag("high")
                        Text("Medium").tag("medium")
                        Text("Low").tag("low")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if hasBitrate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio bitrate").font(.subheadline)
                    Picker("", selection: $audioBitrate) {
                        Text("64").tag(64000)
                        Text("128").tag(128000)
                        Text("192").tag(192000)
                        Text("256").tag(256000)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            HStack {
                if preset.isBuiltIn && PreferencesManager.shared.builtInOverride(named: preset.name) != nil {
                    Button("Reset to Default") {
                        PreferencesManager.shared.clearBuiltInOverride(named: preset.name)
                        onDone()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 340)
    }

    private func save() {
        var s = preset.settings
        if hasQuality {
            if s.jpegQuality != nil { s.jpegQuality = quality }
            if s.heicQuality != nil { s.heicQuality = quality }
            if s.webpQuality != nil { s.webpQuality = quality }
            if s.avifQuality != nil { s.avifQuality = quality }
        }
        if hasResize { s.resizePercent = resize }
        if hasStrip { s.stripMetadata = stripMeta }
        if hasVideo { s.videoPreset = videoPreset }
        if hasBitrate { s.audioBitrate = audioBitrate }

        if preset.isBuiltIn {
            PreferencesManager.shared.setBuiltInOverride(s, named: preset.name)
        } else {
            PreferencesManager.shared.savePreset(name: preset.name, settings: s)
        }
        onDone()
        dismiss()
    }
}

// MARK: - Tips & Tricks

struct TipsPopover: View {
    private struct Tip {
        let icon: String
        let title: String
        let text: String
    }

    private let tips: [Tip] = [
        Tip(icon: "cursorarrow.click", title: "Convert from Finder",
            text: "Right-click any file in Finder and pick a format from Convert File. No need to open the app."),
        Tip(icon: "square.stack.3d.up", title: "Batch convert",
            text: "Select multiple files at once — the menu only shows formats compatible with all of them."),
        Tip(icon: "folder", title: "Convert whole folders",
            text: "Right-click a folder to convert everything inside recursively, mirroring the structure."),
        Tip(icon: "doc.on.doc", title: "Merge & split PDFs",
            text: "Select 2+ PDFs and right-click to merge. Right-click a single PDF to split it into pages."),
        Tip(icon: "waveform", title: "Extract audio from video",
            text: "Right-click a video and choose MP3 or M4A to pull out just the audio track."),
        Tip(icon: "photo.stack", title: "Video to GIF",
            text: "Convert any video to an animated GIF — great for quick shares and bug reports."),
        Tip(icon: "globe", title: "Instant favicon",
            text: "Convert any image to ICO and it is auto-resized to 256×256, ready for the web."),
        Tip(icon: "doc.richtext", title: "Styled Markdown PDFs",
            text: "Pick Modern, Serif, GitHub, or Plain styling for .md conversions in the .pdf format settings."),
        Tip(icon: "slider.horizontal.2.square", title: "One-click presets",
            text: "The Presets tab (Cmd+3) applies quality, resize, and metadata profiles across all formats at once."),
        Tip(icon: "tablecells", title: "Multi-sheet spreadsheets",
            text: "An XLSX with several sheets converts to a folder with one clean CSV per sheet."),
        Tip(icon: "clock.arrow.circlepath", title: "Undo a conversion",
            text: "The History tab lists every output — click the trash icon to move one to the Trash."),
        Tip(icon: "keyboard", title: "Fast navigation",
            text: "Cmd+1...6 switches tabs. The app keeps working in the background after you close the window."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Tips & Tricks")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(tips.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: tips[i].icon)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tips[i].title)
                                    .font(.subheadline.weight(.semibold))
                                Text(tips[i].text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: 400)
    }
}

// MARK: - About

struct AboutTab: View {
    @State private var historyEntries: [ConversionHistoryEntry] = []

    private struct TypeStat: Identifiable {
        let id: String
        let count: Int
    }

    private var successfulEntries: [ConversionHistoryEntry] {
        historyEntries.filter(\.success)
    }

    private var filesConverted: Int {
        successfulEntries.reduce(0) { $0 + max($1.inputFiles.count, 1) }
    }

    private var successRate: Int {
        historyEntries.isEmpty ? 0 : Int((Double(successfulEntries.count) / Double(historyEntries.count) * 100).rounded())
    }

    private var typeStats: [TypeStat] {
        let counts = Dictionary(grouping: successfulEntries, by: { $0.outputFormat.uppercased() })
            .mapValues(\.count)
        let sorted = counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
        var stats = sorted.prefix(5).map { TypeStat(id: $0.key, count: $0.value) }
        let rest = sorted.dropFirst(5).reduce(0) { $0 + $1.value }
        if rest > 0 { stats.append(TypeStat(id: "Other", count: rest)) }
        return stats
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
                    .padding(.top, 24)

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

                GroupBox {
                    if historyEntries.isEmpty {
                        Text("No conversions yet — stats will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 0) {
                                statTile(value: "\(successfulEntries.count)", label: "Conversions")
                                Divider().frame(height: 28)
                                statTile(value: "\(filesConverted)", label: "Files")
                                Divider().frame(height: 28)
                                statTile(value: "\(successRate)%", label: "Success")
                            }

                            Divider()

                            typeChart

                            Text("Based on your last \(historyEntries.count) conversions.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(4)
                    }
                } label: {
                    Label("Your Stats", systemImage: "chart.bar")
                }
                .frame(maxWidth: 340)

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
            }
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .onAppear { historyEntries = ConversionHistoryStore.shared.entries }
    }

    private var typeChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BY TYPE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            let maxCount = typeStats.map(\.count).max() ?? 1
            ForEach(typeStats) { stat in
                HStack(spacing: 8) {
                    Text(stat.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: max(geo.size.width * CGFloat(stat.count) / CGFloat(maxCount), 4))
                    }
                    .frame(height: 8)
                    Text("\(stat.count)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)
                }
            }
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
