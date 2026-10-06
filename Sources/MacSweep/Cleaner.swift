import AppKit
import Foundation

/// Every removal goes to the Trash (recoverable) or through the owning tool (git, brew).
enum Cleaner {
    struct Outcome { let ok: Bool; let detail: String }

    static func perform(_ item: SweepItem) async -> Outcome {
        switch item.action {
        case .trash:
            return await trash(item.paths)

        case .gitWorktree(let repo, let branch):
            guard let path = item.paths.first else { return Outcome(ok: false, detail: tr("没有路径", "No path")) }
            let r = await Task.detached { FS.git(repo, ["worktree", "remove", "--force", path.path]) }.value
            guard r.status == 0 else { return Outcome(ok: false, detail: r.out) }
            _ = await Task.detached { FS.git(repo, ["worktree", "prune"]) }.value
            if let branch {
                // -d (not -D): git refuses if the branch is not merged after all.
                let d = await Task.detached { FS.git(repo, ["branch", "-d", branch]) }.value
                return Outcome(ok: true, detail: tr("已移除 worktree", "Removed worktree") + (d.status == 0 ? tr("，并删除已合并分支 \(branch)", " and deleted merged branch \(branch)") : ""))
            }
            return Outcome(ok: true, detail: tr("已移除 worktree", "Removed worktree"))

        case .brewUninstall(let name):
            guard let brew = FS.brew else { return Outcome(ok: false, detail: tr("找不到 brew", "brew not found")) }
            let r = await Task.detached { FS.run(brew, ["uninstall", name]) }.value
            guard r.status == 0 else { return Outcome(ok: false, detail: r.out) }
            let a = await Task.detached { FS.run(brew, ["autoremove"]) }.value
            let removedDeps = a.out.split(separator: "\n").filter { $0.hasPrefix("Uninstalling") }.count
            return Outcome(ok: true, detail: tr("已卸载 \(name)", "Uninstalled \(name)") + (removedDeps > 0 ? tr("，顺带清掉 \(removedDeps) 个不再需要的依赖", ", plus \(removedDeps) unneeded dependencies") : ""))

        case .brewCleanup:
            guard let brew = FS.brew else { return Outcome(ok: false, detail: tr("找不到 brew", "brew not found")) }
            let r = await Task.detached { FS.run(brew, ["cleanup", "-s", "--prune=all"]) }.value
            return Outcome(ok: r.status == 0, detail: r.status == 0 ? tr("brew cleanup 完成", "brew cleanup done") : r.out)
        }
    }

    static func trash(_ urls: [URL]) async -> Outcome {
        var failed: [URL] = []
        for url in urls where FS.exists(url) {
            do { try FS.fm.trashItem(at: url, resultingItemURL: nil) } catch { failed.append(url) }
        }
        if !failed.isEmpty {
            // Root-owned (App Store) apps and TCC-protected containers: Finder can do it,
            // asking for an admin password if needed.
            let retry = failed
            await MainActor.run { finderDelete(retry) }
            failed = failed.filter(FS.exists)
        }
        if failed.isEmpty { return Outcome(ok: true, detail: tr("已移到废纸篓（\(urls.count) 处）", "Moved to Trash (\(urls.count) locations)")) }
        let list = failed.map(FS.tilde).joined(separator: "\n")
        return Outcome(ok: false, detail: tr("以下位置没有权限移动，可在访达里手动删除，或在「系统设置 › 隐私与安全性 › 完全磁盘访问权限」里允许 MacSweep：\n\(list)", "No permission to move these; delete them in Finder, or allow MacSweep under System Settings › Privacy & Security › Full Disk Access:\n\(list)"))
    }

    @MainActor
    private static func finderDelete(_ urls: [URL]) {
        let list = urls.map { "POSIX file \"\($0.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"" }
        let src = "tell application \"Finder\" to delete {\(list.joined(separator: ", "))}"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
    }

    @MainActor
    static func emptyTrash() -> Bool {
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&err)
        return err == nil
    }

    static var trashURL: URL { FS.url(".Trash") }

    /// nil when the Trash can't be read (no Full Disk Access).
    static func trashSize() -> Int64? {
        guard (try? FS.fm.contentsOfDirectory(atPath: trashURL.path)) != nil else { return nil }
        return FS.size(trashURL)
    }
}
