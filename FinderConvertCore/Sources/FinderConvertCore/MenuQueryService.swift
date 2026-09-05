import Foundation

// The sandboxed Finder extension cannot enumerate folder contents (the
// sandbox has no entitlement for arbitrary or Documents/Desktop reads), so
// it asks the main app - unsandboxed, usually running - over a local
// CFMessagePort. The port name is prefixed with the app group id, which is
// what allows the sandboxed side to look it up.

public enum MenuQuery {
    public static let portName = "\(AppGroup.identifier).menuquery"

    // Extension side: ask the running main app which outputs fit the
    // selection. nil when the app isn't running or didn't answer in time
    public static func sampledOutputs(for urls: [URL], timeout: TimeInterval = 0.5) -> [OutputFormat]? {
        guard let remote = CFMessagePortCreateRemote(nil, portName as CFString) else { return nil }
        defer { CFMessagePortInvalidate(remote) }
        guard let payload = try? JSONEncoder().encode(urls.map(\.path)) else { return nil }

        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            remote, 0, payload as CFData, timeout, timeout,
            CFRunLoopMode.defaultMode.rawValue, &reply
        )
        guard status == kCFMessagePortSuccess,
              let data = reply?.takeRetainedValue() as Data?,
              let raws = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return raws.compactMap(OutputFormat.init(rawValue:))
    }
}

// Main-app side: answers MenuQuery requests on a dedicated thread.
// @unchecked Sendable: `thread` is guarded by `lock`
public final class MenuQueryServer: @unchecked Sendable {
    public static let shared = MenuQueryServer()
    private let lock = NSLock()
    private var thread: Thread?

    private init() {}

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard thread == nil else { return }
        let thread = Thread {
            var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
            guard let port = CFMessagePortCreateLocal(nil, MenuQuery.portName as CFString, menuQueryCallback, &context, nil),
                  let source = CFMessagePortCreateRunLoopSource(nil, port, 0) else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CFRunLoopRun()
        }
        thread.name = "finderconvert-menu-query"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }
}

private func menuQueryCallback(
    _ port: CFMessagePort?,
    _ messageID: Int32,
    _ data: CFData?,
    _ info: UnsafeMutableRawPointer?
) -> Unmanaged<CFData>? {
    let empty = { Unmanaged.passRetained(Data() as CFData) }
    guard let data = data as Data?,
          let paths = try? JSONDecoder().decode([String].self, from: data) else { return empty() }

    let urls = paths.map { URL(fileURLWithPath: $0) }
    let outputs = QuickActionConversionService().sampledOutputs(for: urls)
    guard let reply = try? JSONEncoder().encode(outputs.map(\.rawValue)) else { return empty() }
    return Unmanaged.passRetained(reply as CFData)
}
