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
                print("\n== \(c.title)  " + tr("\(items.count) 项", "\(items.count) items") + "  \(formatBytes(total))")
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

/// `open MacSweep.app --args --space <out>`: runs the space analysis with the app's own
/// permissions and writes the breakdown to a text file.
enum SpaceDump {
    static func run(out: String) -> Never {
        let start = Date()
        let r = SpaceAnalysis.run(progress: SpaceScanner.Progress())
        var lines = [String(format: "took %.1fs, %d files", Date().timeIntervalSince(start), r.scannedFiles),
                     "container total \(formatBytes(r.container.total)) free \(formatBytes(r.container.free))"]
        for v in r.container.volumes { lines.append("  vol \(v.role) \(v.name) \(formatBytes(v.used))") }
        for b in Bucket.allCases { lines.append("\(b.title): \(formatBytes(r.total(b)))") }
        for o in r.owners(in: Set(Bucket.allCases)).prefix(120) {
            lines.append("\n\(formatBytes(o.total).padding(toLength: 10, withPad: " ", startingAt: 0)) [\(o.bucket.title)] \(o.name)")
            for p in o.parts.sorted(by: { $0.size > $1.size }).prefix(6) {
                lines.append("      \(formatBytes(p.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(p.label)  \(p.path ?? "")")
            }
        }
        try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        exit(0)
    }
}
