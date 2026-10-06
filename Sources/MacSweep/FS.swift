import Foundation
import CoreServices

enum FS {
    static let fm = FileManager.default
    static let home = URL(fileURLWithPath: NSHomeDirectory())
    static let library = home.appendingPathComponent("Library")

    static func url(_ relativeToHome: String) -> URL {
        home.appendingPathComponent(relativeToHome)
    }

    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func isDir(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    static func children(_ url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    static func mtime(_ url: URL) -> Date? {
        (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func ctime(_ url: URL) -> Date? {
        (try? fm.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
    }

    /// Allocated size on disk; unreadable subtrees count as zero.
    static func size(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if !isDir(url) || isSymlink(url) {
            let v = try? url.resourceValues(forKeys: keys)
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Fills in sizes concurrently and drops items below `min` bytes.
    static func sized(_ items: [SweepItem], min: Int64 = 0) async -> [SweepItem] {
        await withTaskGroup(of: SweepItem.self) { group in
            for item in items {
                group.addTask {
                    var it = item
                    if it.size == 0 { it.size = it.paths.reduce(0) { $0 + size($1) } }
                    return it
                }
            }
            var out: [SweepItem] = []
            for await it in group where it.size >= min { out.append(it) }
            return out.sorted { $0.size > $1.size }
        }
    }

    static func tilde(_ url: URL) -> String {
        let p = url.path
        return p.hasPrefix(home.path) ? "~" + p.dropFirst(home.path.count) : p
    }

    static func spotlightLastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Full Disk Access is needed to read other apps' Containers and the Trash.
    /// Probes locations only readable with it; the first one that exists decides. (The user
    /// TCC.db is not a reliable probe: newer macOS versions moved it.)
    static func hasFullDiskAccess() -> Bool {
        let probes = ["Library/Containers/com.apple.Safari", "Library/Safari", "Library/Mail",
                      "Library/Application Support/com.apple.TCC/TCC.db"]
        for rel in probes {
            let url = url(rel)
            guard fm.fileExists(atPath: url.path) else { continue }
            if isDir(url) { return (try? fm.contentsOfDirectory(atPath: url.path)) != nil }
            return (try? FileHandle(forReadingFrom: url))?.closeFile() != nil
        }
        return false
    }

    /// Folders macOS asks the user about (TCC). Reading them without Full Disk Access pops a
    /// permission dialog, and every rebuild of an ad-hoc-signed app forgets the answer.
    static let promptingFolders = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Library/Mobile Documents"]

    static func isPrompting(_ url: URL) -> Bool {
        promptingFolders.contains {
            let p = home.appendingPathComponent($0).path
            return url.path == p || url.path.hasPrefix(p + "/")
        }
    }

    /// True when we may read `url` without triggering a permission dialog.
    static func mayRead(_ url: URL) -> Bool { !isPrompting(url) || hasFullDiskAccess() }

    // MARK: processes

    static let toolPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    @discardableResult
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = toolPath
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static var brew: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { fm.isExecutableFile(atPath: $0) }
    }

    static func git(_ repo: URL, _ args: [String]) -> (status: Int32, out: String) {
        run("/usr/bin/git", ["-C", repo.path] + args)
    }
}
