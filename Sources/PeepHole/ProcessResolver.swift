import AppKit
import Darwin

/// Human-friendly identity of a process, plus the app it belongs to.
struct ProcessIdentity {
    let name: String          // full process name, e.g. "Google Chrome Helper"
    let executablePath: String?
    let groupKey: String      // processes sharing this key are merged in "group by app" mode
    let groupName: String     // e.g. "Google Chrome"
    let appBundlePath: String?
}

/// Resolves PIDs to names, owning apps and icons. Results are cached.
@MainActor
final class ProcessResolver {
    private var iconCache: [String: NSImage] = [:]

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    /// Private libsystem SPI Activity Monitor uses to attribute XPC services
    /// (e.g. com.apple.WebKit.Networking) to the app that spawned them.
    private let responsibleFn: ResponsibleFn? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    func resolve(pid: Int32, fallbackName: String) -> ProcessIdentity {
        let path = Self.executablePath(for: pid)
        let name = path.map { ($0 as NSString).lastPathComponent } ?? fallbackName

        // XPC services and app extensions live outside their host app's bundle,
        // so attribute them to whichever app is responsible for them.
        if let path, path.contains(".xpc/") || path.contains(".appex/"),
           let responsible = responsibleFn?(pid), responsible > 0, responsible != pid,
           let hostPath = Self.executablePath(for: responsible),
           let hostApp = Self.outermostAppBundle(in: hostPath) {
            return ProcessIdentity(name: name, executablePath: path,
                                   groupKey: "app:" + hostApp,
                                   groupName: Self.appName(forBundle: hostApp),
                                   appBundlePath: hostApp)
        }

        if let path, let app = Self.outermostAppBundle(in: path) {
            return ProcessIdentity(name: name, executablePath: path,
                                   groupKey: "app:" + app,
                                   groupName: Self.appName(forBundle: app),
                                   appBundlePath: app)
        }

        return ProcessIdentity(name: name, executablePath: path,
                               groupKey: "exe:" + (path ?? name),
                               groupName: name,
                               appBundlePath: nil)
    }

    func icon(forBundle path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        iconCache[path] = image
        return image
    }

    // MARK: - Helpers

    static func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// "/Applications/Google Chrome.app/Contents/Frameworks/.../Helper.app/..."
    /// becomes "/Applications/Google Chrome.app".
    static func outermostAppBundle(in path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return components[...index].joined(separator: "/")
    }

    static func appName(forBundle path: String) -> String {
        if let bundle = Bundle(path: path) {
            let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary ?? [:]
            if let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String,
               !name.isEmpty {
                return name
            }
        }
        return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
