import Foundation

/// Third-party apps ranked by how long ago they were last used.
struct AppScanner {
    let inv: AppInventory
    let running: Set<String>   // lowercased bundle IDs

    /// Where an app keeps its stuff in ~/Library (what AppCleaner would remove).
    static func related(bundleID: String?, name: String) -> [URL] {
        let lib = FS.library
        var rels: [String] = ["Application Support/\(name)", "Logs/\(name)", "Caches/\(name)"]
        if let id = bundleID {
            rels += ["Application Support/\(id)", "Caches/\(id)", "Containers/\(id)", "HTTPStorages/\(id)",
                     "HTTPStorages/\(id).binarycookies", "WebKit/\(id)", "Logs/\(id)",
                     "Preferences/\(id).plist", "Saved Application State/\(id).savedState", "Application Scripts/\(id)"]
        }
        if !FS.hasFullDiskAccess() { rels.removeAll { $0.hasPrefix("Containers/") } }
        return rels.map { lib.appendingPathComponent($0) }.filter(FS.exists)
    }

    func scan() async -> [SweepItem] {
        let now = Date()
        let items: [SweepItem] = inv.userApps.compactMap { app in
            let id = app.bundleID?.lowercased()
            if let id, id.hasPrefix("com.apple.") || running.contains(id) || id == Bundle.main.bundleIdentifier?.lowercased() { return nil }

            let data = Self.related(bundleID: app.bundleID, name: app.name)
            // Preference files and containers are touched every time an app runs; Spotlight's
            // kMDItemLastUsedDate is often missing, so take whichever is newer.
            let traces = data.compactMap(FS.mtime)
            let used = ([FS.spotlightLastUsed(app.url)].compactMap { $0 } + traces).max()
            let installed = FS.ctime(app.url) ?? now

            let ref = used ?? installed
            let days = Int(now.timeIntervalSince(ref) / 86400)
            let risk: Risk = days > 180 ? .review : .careful
            var reason = used == nil ? "没有使用记录，安装于 \(formatAge(installed))" : "最后使用于 \(formatAge(used))"
            if !data.isEmpty { reason += "；连同 \(data.count) 处 Library 数据一起移除" }

            return SweepItem(id: "app:\(app.url.path)", category: .apps, title: app.name,
                             subtitle: FS.tilde(app.url), paths: [app.url] + data,
                             lastUsed: used, risk: risk, reason: reason, iconURL: app.url)
        }
        // Steam/Epic game stubs and aliases are a few KB; not worth listing.
        return await FS.sized(items, min: 2 << 20).sorted { $0.lastUsedSort < $1.lastUsedSort }
    }
}
