import Foundation

/// Data left in ~/Library by apps that are no longer installed.
struct OrphanScanner {
    let inv: AppInventory

    private enum Kind { case data, cache, prefs, agent }

    private static let locations: [(String, Kind)] = [
        ("Application Support", .data),
        ("Containers", .data),
        ("Group Containers", .data),
        ("Caches", .cache),
        ("HTTPStorages", .cache),
        ("WebKit", .cache),
        ("Logs", .cache),
        ("Saved Application State", .cache),
        ("Application Scripts", .cache),
        ("Preferences", .prefs),
        ("LaunchAgents", .agent),
    ]

    /// Folder names macOS itself owns that do not look like com.apple.*.
    private static let systemNames: Set<String> = Set([
        "AddressBook", "CallHistoryDB", "CallHistoryTransactions", "CloudDocs", "CrashReporter", "DiskImages",
        "FaceTime", "FileProvider", "Knowledge", "MobileSync", "SyncServices", "iCloud", "icdd", "Animoji",
        "AccessibilityBundles", "DifferentialPrivacy", "Dock", "FontRegistry", "homed", "networkserviceproxy",
        "Quick Look", "Spotlight", "TrustedPeersHelper", "videosubscriptionsd", "CoreParsec", "identityservicesd",
        "ContextStoreAgent", "stickersd", "App Store", "AppStore", "default.store", "locationaccessstored",
        "Safari", "Mail", "Photos", "Music", "Calendars", "Reminders", "Notes", "Messages", "Shortcuts",
        "Wallpaper", "ByHost", "AppleMediaServices", "GeoServices", "familycircled", "Maps", "News", "Stocks",
        "Weather", "Siri", "Assistant", "SiriTTS", "Accounts", "Mobile Documents", "Metadata", "Fonts",
        "Keychains", "Sharing", "Trial", "StatusKit", "PersonalizationPortrait", "ScreenTime", "MediaRemote",
        "DiagnosticReports", "Bluetooth", "CallServices", "Passes", "PassKit", "HomeKit", "IdentityServices",
        "SESStorage", "BiomeAgent", "Biome", "Daemon Containers", "Containers", "Group Containers",
        "networkd", "rapportd", "remindd", "tipsd", "suggestd", "ScreenRecordings", "MusicKit",
        "AppleIntelligence", "Intelligence", "GameKit", "Translation", "Freeform", "Journal",
        "com.crashlytics", "Google", "Microsoft", "Adobe", "JetBrains", "Logi",
        "CrashpadMetrics", "Crashpad", "SentryCrash", "Sentry", "Caches", "CoreSimulator", "SiriEntityCache",
        "PassKit", "Animoji", "Developer", "Xcode", "IntelligencePlatform", "ModelCatalog",
    ].map(AppInventory.normalize))

    private static let uuidLike = try! NSRegularExpression(pattern: "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-")
    private static let teamPrefix = try! NSRegularExpression(pattern: "^[A-Z0-9]{10}\\.")

    func scan() async -> [SweepItem] {
        struct Group { var display: String; var paths: [URL] = []; var hasData = false; var newest: Date? }
        var groups: [String: Group] = [:]

        // Without Full Disk Access, touching other apps' containers only triggers
        // "Data Access Blocked" notifications and returns nothing.
        let fda = FS.hasFullDiskAccess()
        for (dirName, kind) in Self.locations {
            if !fda && dirName.hasSuffix("Containers") { continue }
            let dir = FS.library.appendingPathComponent(dirName)
            for child in FS.children(dir) {
                // Loose files in Logs are rotated logs (warp.log.old.0), not per-app folders.
                if dirName == "Logs" && !FS.isDir(child) { continue }
                guard let key = Self.key(for: child.lastPathComponent, kind: kind) else { continue }
                if Self.isSystem(key) { continue }
                let bundleLike = Self.isBundleLike(key)
                if kind == .prefs && !bundleLike { continue }
                if bundleLike ? inv.owns(bundleID: key) : inv.owns(name: key) { continue }

                let gk = bundleLike ? key.lowercased() : AppInventory.normalize(key)
                var g = groups[gk] ?? Group(display: key)
                g.paths.append(child)
                if kind == .data { g.hasData = true }
                if let m = FS.mtime(child), m > (g.newest ?? .distantPast) { g.newest = m }
                groups[gk] = g
            }
        }

        let items: [SweepItem] = groups.map { gk, g in
            let bundleLike = Self.isBundleLike(g.display)
            let days = g.newest.map { Int(Date().timeIntervalSince($0) / 86400) } ?? 9999
            var risk: Risk = g.hasData ? .review : .safe
            var reasons: [String] = [bundleLike ? tr("找不到 bundle ID 对应的已安装软件", "No installed app matches this bundle ID") : tr("按名称找不到对应的软件或命令行工具", "No app or CLI tool matches this name")]
            if g.hasData { reasons.append(tr("含用户数据（设置、存档等），确认不要了再删", "Contains user data (settings, saves, etc.); delete only if you're sure")) }
            if !bundleLike { risk = max(risk, .review) }
            if let v = bundleLike ? inv.sameVendorApp(g.display) : nil { reasons.append(tr("同厂商的「\(v)」还装着", "\"\(v)\" from the same vendor is still installed")); risk = max(risk, .review) }
            if days < 14 { reasons.append(tr("\(days) 天内还有写入，可能仍有程序在用", days == 0 ? "Written to today; may still be in use" : "Written to \(days) day\(days == 1 ? "" : "s") ago; may still be in use")); risk = .careful }
            let places = Set(g.paths.map { $0.deletingLastPathComponent().lastPathComponent }).sorted().joined(separator: tr("、", ", "))
            return SweepItem(id: "orphan:\(gk)", category: .orphans, title: g.display,
                             subtitle: tr("\(g.paths.count) 处：\(places)", "\(g.paths.count) location\(g.paths.count == 1 ? "" : "s"): \(places)"), paths: g.paths,
                             lastUsed: g.newest, risk: risk, reason: reasons.joined(separator: tr("；", "; ")))
        }
        return await FS.sized(items, min: 256 * 1024)
    }

    private static func key(for raw: String, kind: Kind) -> String? {
        if raw.hasPrefix(".") { return nil }
        var k = raw
        for ext in [".plist", ".savedState", ".binarycookies", ".log"] where k.hasSuffix(ext) {
            k = String(k.dropLast(ext.count))
        }
        if k.hasPrefix("group.") { k = String(k.dropFirst(6)) }
        let r = NSRange(k.startIndex..., in: k)
        if teamPrefix.firstMatch(in: k, range: r) != nil { k = String(k.dropFirst(11)) }
        if k.isEmpty || uuidLike.firstMatch(in: k, range: NSRange(k.startIndex..., in: k)) != nil { return nil }
        return k
    }

    static func isBundleLike(_ k: String) -> Bool {
        !k.contains(" ") && k.split(separator: ".").count >= 3
    }

    private static func isSystem(_ k: String) -> Bool {
        let l = k.lowercased()
        if l.hasPrefix("com.apple.") || l.hasPrefix("apple") || l.contains(".apple.") || l.hasPrefix("systemgroup.") { return true }
        // macOS daemons: lowercase single word ending in "d" (askpermissiond, parsecd, ...).
        if k.count >= 6, k == l, l.hasSuffix("d"), l.allSatisfy(\.isLetter) { return true }
        return systemNames.contains(AppInventory.normalize(k))
    }
}
