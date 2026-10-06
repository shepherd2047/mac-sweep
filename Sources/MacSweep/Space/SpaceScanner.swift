import Foundation
import os

/// One folder (or big file) on the Data volume. Paths are as the user sees them ("/Users/you"),
/// not the "/System/Volumes/Data" mount they are read through.
final class SpaceNode: Identifiable, @unchecked Sendable {
    let path: String
    let name: String
    let isDir: Bool
    var size: Int64 = 0
    var children: [SpaceNode] = []
    /// Small files and tiny folders directly inside, not kept as nodes.
    var smallSize: Int64 = 0
    var smallCount = 0
    var unreadable = false
    weak var parent: SpaceNode?

    var id: String { path }

    init(path: String, name: String, isDir: Bool) {
        self.path = path
        self.name = name
        self.isDir = isDir
    }

    func child(_ name: String) -> SpaceNode? { children.first { $0.name == name } }

    func node(at path: String) -> SpaceNode? {
        var n: SpaceNode? = self
        for comp in path.split(separator: "/") { n = n?.child(String(comp)) }
        return n
    }
}

enum SpaceScanner {
    static let dataRoot = "/System/Volumes/Data"
    static let keepFile: Int64 = 10 << 20   // files at least this big get their own row
    static let keepDir: Int64 = 1 << 20

    final class Progress: @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (files: 0, path: ""))
        func add(_ n: Int, _ path: String) { state.withLock { $0.files += n; $0.path = path } }
        var value: (files: Int, path: String) { state.withLock { $0 } }
    }

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey,
                                                 .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    /// Walks the whole Data volume. `skip` holds display paths left alone (TCC-protected
    /// folders when the app has no Full Disk Access, so macOS does not prompt).
    static func scan(skip: Set<String>, progress: Progress) -> SpaceNode {
        let root = SpaceNode(path: "/", name: "Macintosh HD", isDir: true)
        fill(root, url: URL(fileURLWithPath: dataRoot), depth: 0, skip: skip, progress)
        return root
    }

    private static func fill(_ node: SpaceNode, url: URL, depth: Int, skip: Set<String>, _ p: Progress) {
        if skip.contains(node.path) { node.unreadable = true; return }
        let list: [URL]
        do {
            list = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
        } catch {
            node.unreadable = true
            return
        }
        var dirs: [(URL, SpaceNode)] = []
        var kept: [SpaceNode] = []
        var small: Int64 = 0
        var smallCount = 0
        let keySet = Set(keys)
        for c in list {
            guard let v = try? c.resourceValues(forKeys: keySet), v.isSymbolicLink != true else { continue }
            let name = c.lastPathComponent
            let path = node.path == "/" ? "/" + name : node.path + "/" + name
            if v.isDirectory == true {
                if v.isVolume == true { continue } // mounted disks, simulator runtimes, autofs
                dirs.append((c, SpaceNode(path: path, name: name, isDir: true)))
            } else {
                let s = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                if s >= keepFile {
                    let f = SpaceNode(path: path, name: name, isDir: false)
                    f.size = s
                    kept.append(f)
                } else {
                    small += s
                    smallCount += 1
                }
            }
        }
        p.add(list.count, node.path)

        if depth < 4 && dirs.count > 1 {
            DispatchQueue.concurrentPerform(iterations: dirs.count) { i in
                fill(dirs[i].1, url: dirs[i].0, depth: depth + 1, skip: skip, p)
            }
        } else {
            for (u, n) in dirs { fill(n, url: u, depth: depth + 1, skip: skip, p) }
        }

        for (_, d) in dirs {
            if d.size >= keepDir || d.unreadable {
                kept.append(d)
            } else {
                small += d.size
                smallCount += 1
            }
        }
        for k in kept { k.parent = node }
        node.children = kept.sorted { $0.size > $1.size }
        node.smallSize = small
        node.smallCount = smallCount
        node.size = kept.reduce(small) { $0 + $1.size }
    }
}

/// APFS volumes sharing the container with the startup disk (System, Preboot, VM, Data, ...).
struct VolumeUsage {
    let name: String
    let role: String
    let used: Int64
}

struct ContainerUsage {
    var total: Int64 = 0
    var free: Int64 = 0
    var volumes: [VolumeUsage] = []

    func used(role: String) -> Int64 { volumes.filter { $0.role == role }.reduce(0) { $0 + $1.used } }

    static func read() -> ContainerUsage {
        var sfs = statfs()
        guard statfs(SpaceScanner.dataRoot, &sfs) == 0 else { return ContainerUsage() }
        let dataDev = withUnsafeBytes(of: sfs.f_mntfromname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            .replacingOccurrences(of: "/dev/", with: "")

        let (_, out) = FS.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"])
        guard let data = out.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let containers = plist["Containers"] as? [[String: Any]] else { return ContainerUsage() }
        for c in containers {
            let vols = c["Volumes"] as? [[String: Any]] ?? []
            guard vols.contains(where: { ($0["DeviceIdentifier"] as? String) == dataDev }) else { continue }
            var u = ContainerUsage()
            u.total = (c["CapacityCeiling"] as? NSNumber)?.int64Value ?? 0
            u.free = (c["CapacityFree"] as? NSNumber)?.int64Value ?? 0
            u.volumes = vols.map {
                VolumeUsage(name: $0["Name"] as? String ?? "?",
                            role: ($0["Roles"] as? [String])?.first ?? "",
                            used: ($0["CapacityInUse"] as? NSNumber)?.int64Value ?? 0)
            }
            return u
        }
        return ContainerUsage()
    }
}
