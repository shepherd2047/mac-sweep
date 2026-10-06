import AppKit
import Foundation

/// `MacSweep --dump`: run every scanner and print the results without opening a window.
enum Dump {
    static func run() -> Never {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let start = Date()
            let inv = AppInventory()
            print("inventory: \(inv.bundleIDs.count) bundle IDs, \(inv.names.count) names, \(inv.userApps.count) user apps")
            let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
            let orphans = await OrphanScanner(inv: inv).scan()
            let claimed = Set(orphans.flatMap { $0.paths.map(\.path) })
            let results: [(Category, [SweepItem])] = [
                (.orphans, orphans),
                (.caches, await CacheScanner(inv: inv, claimed: claimed).scan()),
                (.apps, await AppScanner(inv: inv, running: running).scan()),
                (.large, await LargeScanner().scan()),
                (.dev, await DevScanner().scan()),
            ]
            for (c, items) in results {
                let total = items.reduce(0) { $0 + $1.size }
                print("\n== \(c.title)  \(items.count) 项  \(formatBytes(total))")
                for i in items {
                    let size = formatBytes(i.size).padding(toLength: 10, withPad: " ", startingAt: 0)
                    let risk = i.risk.title.padding(toLength: 4, withPad: "　", startingAt: 0)
                    print("  \(size) \(risk) \(i.title)  [\(formatAge(i.lastUsed))]  \(i.reason)")
                }
            }
            print(String(format: "\nscan took %.1fs", Date().timeIntervalSince(start)))
            done.signal()
        }
        done.wait()
        exit(0)
    }
}

/// `open MacSweep.app --args --check-access <out>`: records which protected locations this
/// build can read. Must be launched via `open` so TCC attributes access to MacSweep itself
/// rather than to the terminal that started it.
enum AccessCheck {
    static func run(out: String) -> Never {
        let probes = ["Library/Application Support/com.apple.TCC/TCC.db", ".Trash", "Library/Safari",
                      "Library/Mail", "Library/Messages", "Library/Containers/com.apple.Safari",
                      "Library/Containers", "Downloads", "Documents", "Desktop"]
        var lines = ["bundle: \(Bundle.main.bundlePath)", "hasFullDiskAccess(): \(FS.hasFullDiskAccess())"]
        for p in probes {
            let url = FS.url(p)
            let exists = FS.fm.fileExists(atPath: url.path)
            var result = "missing"
            if exists {
                if FS.isDir(url) {
                    do { _ = try FS.fm.contentsOfDirectory(atPath: url.path); result = "OK" }
                    catch { result = "DENIED (\((error as NSError).code))" }
                } else {
                    do { let h = try FileHandle(forReadingFrom: url); _ = try h.read(upToCount: 16); try h.close(); result = "OK" }
                    catch { result = "DENIED (\((error as NSError).code))" }
                }
            }
            lines.append("\(p): \(result)")
        }
        try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        exit(0)
    }
}
