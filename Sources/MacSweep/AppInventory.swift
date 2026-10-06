import Foundation

struct InstalledApp: Hashable {
    let url: URL
    let bundleID: String?
    let name: String
}

/// Everything installed on the machine that could own data in ~/Library:
/// app bundles (and their nested helpers/extensions), command-line tools, brew formulae.
final class AppInventory: @unchecked Sendable {
    /// Top-level apps in /Applications and ~/Applications (what the user thinks of as "their apps").
    private(set) var userApps: [InstalledApp] = []
    private(set) var bundleIDs: Set<String> = []        // lowercased
    private(set) var names: Set<String> = []            // normalized app/tool/vendor names
    private(set) var appNameByID: [String: String] = [:] // lowercased id -> display name
    private(set) var appURLByID: [String: URL] = [:]     // lowercased id -> bundle URL
    private(set) var appIDByName: [String: String] = [:] // normalized display/bundle name -> lowercased id

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    init() {
        var appURLs = Set<URL>()

        // Spotlight knows about apps anywhere (Steam games, apps inside tool folders, ...).
        let (_, out) = FS.run("/usr/bin/mdfind", ["kMDItemContentType == 'com.apple.application-bundle'"])
        for line in out.split(separator: "\n") where line.hasPrefix("/") {
            let p = String(line)
            if p.contains("/.Trash/") || p.contains("/Library/Caches/") { continue }
            appURLs.insert(URL(fileURLWithPath: p))
        }

        let topRoots = [URL(fileURLWithPath: "/Applications"), FS.url("Applications")]
        let systemRoots = [URL(fileURLWithPath: "/System/Applications"),
                           URL(fileURLWithPath: "/System/Applications/Utilities"),
                           URL(fileURLWithPath: "/System/Library/CoreServices")]
        var top: [URL] = []
        for root in topRoots {
            for c in FS.children(root) {
                if c.pathExtension == "app" { top.append(c) }
                else if FS.isDir(c) { top += FS.children(c).filter { $0.pathExtension == "app" } }
            }
        }
        appURLs.formUnion(top)
        for root in systemRoots { appURLs.formUnion(FS.children(root).filter { $0.pathExtension == "app" }) }

        for url in appURLs { register(bundle: url) }

        // Command-line tools leave data in Application Support too ("uv", "gh", "deno", ...).
        let binDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/homebrew/Cellar", "/opt/homebrew/Caskroom",
                       "/opt/homebrew/lib/node_modules", "/usr/local/Cellar"].map { URL(fileURLWithPath: $0) }
            + [".local/bin", ".cargo/bin", ".bun/bin", "go/bin", ".deno/bin"].map { FS.url($0) }
        for d in binDirs {
            for c in FS.children(d) { addName(c.deletingPathExtension().lastPathComponent) }
        }

        let topSet = Set(top.map(\.standardizedFileURL))
        userApps = topSet.compactMap { url in
            guard !FS.isSymlink(url) else { return nil }
            let b = Bundle(url: url)
            let name = url.deletingPathExtension().lastPathComponent
            return InstalledApp(url: url, bundleID: b?.bundleIdentifier, name: name)
        }.sorted { $0.name < $1.name }
    }

    private func addName(_ s: String) {
        let n = Self.normalize(s)
        if n.count >= 2 { names.insert(n) }
    }

    private func register(bundle url: URL, depth: Int = 0) {
        guard let b = Bundle(url: url) else { return }
        let display = url.deletingPathExtension().lastPathComponent
        addName(display)
        for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            if let v = b.object(forInfoDictionaryKey: key) as? String { addName(v) }
        }
        if let id = b.bundleIdentifier {
            let lid = id.lowercased()
            bundleIDs.insert(lid)
            if depth == 0 {
                appNameByID[lid] = appNameByID[lid] ?? display
                appURLByID[lid] = appURLByID[lid] ?? url
                for n in [display, b.object(forInfoDictionaryKey: "CFBundleName") as? String,
                          b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String].compactMap({ $0 }) {
                    let k = Self.normalize(n)
                    if k.count >= 3, appIDByName[k] == nil { appIDByName[k] = lid }
                }
            }
            let parts = lid.split(separator: ".")
            if parts.count >= 2 { addName(String(parts[1])) } // vendor, e.g. "google" for com.google.Chrome
        }
        guard depth < 2 else { return }
        // Helpers, login items and extensions have their own bundle IDs and containers.
        let contents = url.appendingPathComponent("Contents")
        for sub in ["PlugIns", "Library/LoginItems", "XPCServices", "Library/LaunchServices", "Helpers", "Library/SystemExtensions", "Extensions"] {
            for c in FS.children(contents.appendingPathComponent(sub)) where ["app", "appex", "xpc", "systemextension"].contains(c.pathExtension) {
                register(bundle: c, depth: depth + 1)
            }
        }
    }

    /// Display name of the installed app owning a bundle-ID-like key, if any.
    func appName(forID key: String) -> String? {
        let k = key.lowercased()
        if let n = appNameByID[k] { return n }
        return appNameByID.first { k.hasPrefix($0.key + ".") }?.value
    }

    /// Bundle URL of the installed app owning a bundle-ID-like key, for its icon.
    func appURL(forID key: String) -> URL? {
        let k = key.lowercased()
        if let u = appURLByID[k] { return u }
        return appURLByID.first { k.hasPrefix($0.key + ".") }?.value
    }

    func owns(bundleID key: String) -> Bool {
        let k = key.lowercased()
        if bundleIDs.contains(k) { return true }
        for id in bundleIDs where k.hasPrefix(id + ".") || id.hasPrefix(k + ".") { return true }
        // Same product under a different vendor prefix: com.foo.Steam vs com.valvesoftware.steam
        if let last = k.split(separator: ".").last, names.contains(Self.normalize(String(last))), last.count >= 4 { return true }
        return false
    }

    func owns(name key: String) -> Bool {
        let n = Self.normalize(key)
        if n.count < 3 { return true } // too ambiguous to call it an orphan
        if names.contains(n) { return true }
        for name in names where name.count >= 4 && (n.contains(name) || name.contains(n) && n.count >= 4) { return true }
        return false
    }

    /// Installed apps sharing the vendor part of a bundle ID (com.tencent.*).
    func sameVendorApp(_ key: String) -> String? {
        let parts = key.lowercased().split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let vendor = parts[0] + "." + parts[1]
        return appNameByID.first { $0.key.hasPrefix(vendor + ".") }?.value
    }
}
