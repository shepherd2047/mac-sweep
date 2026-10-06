import Foundation

/// Developer leftovers: git worktrees, old editor extensions, Xcode caches, Homebrew, stale node_modules.
struct DevScanner {
    static let projectRoots = ["projects", "dev", "code", "Developer", "src", "repos", "work", "Documents/GitHub"]

    func scan() async -> [SweepItem] {
        async let wt = worktreesAndNodeModules()
        async let ext = editorExtensions()
        async let brew = homebrew()
        var items = xcode() + (await ext)
        items += await wt
        items += await brew
        return await FS.sized(items, min: 1 << 20)
    }

    // MARK: git worktrees + stale node_modules

    private func worktreesAndNodeModules() -> [SweepItem] {
        var repos: [URL] = []
        var nodeModules: [URL] = []
        let skip: Set<String> = ["node_modules", ".build", "build", "DerivedData", "Pods", ".venv", "venv", ".git", "target", "dist"]

        for root in Self.projectRoots.map(FS.url) where FS.mayRead(root) && FS.isDir(root) {
            guard let e = FS.fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                           options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in e {
                if e.level > 5 { e.skipDescendants(); continue }
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let name = url.lastPathComponent
                if name == ".git" { repos.append(url.deletingLastPathComponent()) }
                if name == "node_modules" { nodeModules.append(url) }
                if skip.contains(name) || name == "worktrees" { e.skipDescendants() }
            }
        }

        var items: [SweepItem] = []
        for repo in repos { items += worktrees(of: repo) }

        let now = Date()
        for nm in nodeModules {
            let project = nm.deletingLastPathComponent()
            let touched = [project.appendingPathComponent("package.json"), project].compactMap(FS.mtime).max()
            let days = touched.map { Int(now.timeIntervalSince($0) / 86400) } ?? 0
            guard days >= 60 else { continue }
            items.append(SweepItem(id: "dev:\(nm.path)", category: .dev, title: "node_modules · \(project.lastPathComponent)",
                                   subtitle: FS.tilde(nm), paths: [nm], lastUsed: touched, risk: .review,
                                   reason: tr("项目 \(days) 天没动过；需要时 npm install 即可恢复", "Project untouched for \(days) days; npm install restores it when needed")))
        }
        return items
    }

    private func worktrees(of repo: URL) -> [SweepItem] {
        let (status, out) = FS.git(repo, ["worktree", "list", "--porcelain"])
        guard status == 0 else { return [] }
        var blocks: [[String: String]] = []
        var cur: [String: String] = [:]
        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { if !cur.isEmpty { blocks.append(cur) }; cur = [:]; continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            cur[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        if !cur.isEmpty { blocks.append(cur) }
        guard blocks.count > 1, let mainBranch = blocks[0]["branch"]?.replacingOccurrences(of: "refs/heads/", with: "") else { return [] }

        return blocks.dropFirst().compactMap { b in
            guard let path = b["worktree"], b["prunable"] == nil, b["bare"] == nil else { return nil }
            let url = URL(fileURLWithPath: path)
            guard FS.exists(url) else { return nil }
            let branch = b["branch"]?.replacingOccurrences(of: "refs/heads/", with: "")
            let head = branch ?? b["HEAD"] ?? "HEAD"
            let dirty = FS.git(url, ["status", "--porcelain"]).out.split(separator: "\n").count
            let ahead = Int(FS.git(repo, ["rev-list", "--count", "\(mainBranch)..\(head)"]).out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let locked = b["locked"] != nil

            var reasons: [String] = []
            var risk: Risk = .safe
            if ahead > 0 { reasons.append(tr("有 \(ahead) 个提交没合并进 \(mainBranch)", "\(ahead) commits not merged into \(mainBranch)")); risk = .careful }
            if dirty > 0 { reasons.append(tr("有 \(dirty) 个未提交的改动", "\(dirty) uncommitted changes")); risk = .careful }
            if locked { reasons.append(tr("worktree 被锁定（可能有程序在用）", "worktree is locked (may be in use)")); risk = .careful }
            if reasons.isEmpty { reasons.append(tr("已全部合并进 \(mainBranch)、没有改动，可放心删除", "Fully merged into \(mainBranch) with no changes; safe to delete")) }

            return SweepItem(id: "wt:\(path)", category: .dev,
                             title: "worktree · \(repo.lastPathComponent) · \(branch ?? "detached")",
                             subtitle: FS.tilde(url), paths: [url], lastUsed: FS.mtime(url), risk: risk,
                             reason: reasons.joined(separator: tr("；", "; ")),
                             action: .gitWorktree(repo: repo, branch: ahead == 0 ? branch : nil))
        }
    }

    // MARK: editors

    private func editorExtensions() -> [SweepItem] {
        let editors = [(".vscode", "VS Code"), (".vscode-insiders", "VS Code Insiders"), (".cursor", "Cursor"),
                       (".antigravity", "Antigravity"), (".windsurf", "Windsurf"), (".vscode-oss", "VSCodium")]
        var items: [SweepItem] = []
        for (dir, editor) in editors {
            let extDir = FS.url("\(dir)/extensions")
            guard let data = try? Data(contentsOf: extDir.appendingPathComponent("extensions.json")),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            let active = Set(list.compactMap { $0["relativeLocation"] as? String })
            guard !active.isEmpty else { continue }
            for c in FS.children(extDir) where FS.isDir(c) && !c.lastPathComponent.hasPrefix(".") && !active.contains(c.lastPathComponent) {
                items.append(SweepItem(id: "dev:\(c.path)", category: .dev, title: tr("\(editor) 旧扩展 · \(c.lastPathComponent)", "\(editor) old extension · \(c.lastPathComponent)"),
                                       subtitle: FS.tilde(c), paths: [c], lastUsed: FS.mtime(c), risk: .safe,
                                       reason: tr("编辑器已经在用这个扩展的新版本", "The editor already uses a newer version of this extension")))
            }
        }
        return items
    }

    // MARK: Xcode

    private func xcode() -> [SweepItem] {
        let list: [(String, String, Risk, String)] = [
            ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData", .safe, tr("编译中间产物，下次编译自动重建", "Build intermediates; rebuilt on next build")),
            ("Library/Developer/Xcode/iOS DeviceSupport", "iOS DeviceSupport", .review, tr("连接真机时生成的符号文件，再连会重新生成", "Symbol files from connected devices; regenerated on next connect")),
            ("Library/Developer/Xcode/watchOS DeviceSupport", "watchOS DeviceSupport", .review, tr("连接手表时生成的符号文件", "Symbol files from connected watches")),
            ("Library/Developer/CoreSimulator/Caches", tr("模拟器缓存", "Simulator cache"), .safe, tr("模拟器 dyld 缓存，自动重建", "Simulator dyld cache; rebuilt automatically")),
            ("Library/Developer/Xcode/Archives", "Xcode Archives", .careful, tr("打包归档；要保留上架版本的 dSYM 就别删", "App archives; keep them if you need dSYMs for released builds")),
            ("Library/Caches/com.apple.dt.Xcode", tr("Xcode 缓存", "Xcode cache"), .safe, tr("Xcode 自身缓存", "Xcode's own cache")),
        ]
        return list.compactMap { rel, title, risk, reason in
            let url = FS.url(rel)
            guard FS.exists(url) else { return nil }
            return SweepItem(id: "dev:\(url.path)", category: .dev, title: title, subtitle: "~/" + rel,
                             paths: [url], lastUsed: FS.mtime(url), risk: risk, reason: reason)
        }
    }

    // MARK: Homebrew

    private func homebrew() async -> [SweepItem] {
        guard let brew = FS.brew else { return [] }
        var items: [SweepItem] = []

        let cache = URL(fileURLWithPath: FS.run(brew, ["--cache"]).out.trimmingCharacters(in: .whitespacesAndNewlines))
        if FS.exists(cache) {
            items.append(SweepItem(id: "brew:cleanup", category: .dev, title: tr("Homebrew 下载缓存和旧版本", "Homebrew download cache and old versions"),
                                   subtitle: FS.tilde(cache), paths: [cache], risk: .safe,
                                   reason: tr("执行 brew cleanup -s --prune=all", "Runs brew cleanup -s --prune=all"), action: .brewCleanup))
        }

        // Leaves: installed on request and nothing else depends on them.
        let (st, json) = FS.run(brew, ["info", "--json=v2", "--installed"])
        guard st == 0, let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]] else { return items }
        var dependedOn = Set<String>()
        for f in formulae { for d in (f["dependencies"] as? [String]) ?? [] { dependedOn.insert(d) } }
        let prefix = URL(fileURLWithPath: brew).deletingLastPathComponent().deletingLastPathComponent()
        for f in formulae {
            guard let name = f["name"] as? String, !dependedOn.contains(name),
                  let inst = f["installed"] as? [[String: Any]], inst.contains(where: { $0["installed_on_request"] as? Bool == true }) else { continue }
            let cellar = prefix.appendingPathComponent("Cellar/\(name)")
            let desc = (f["desc"] as? String).map { tr("：\($0)", ": \($0)") } ?? ""
            items.append(SweepItem(id: "brew:\(name)", category: .dev, title: tr("brew 包 · \(name)", "brew package · \(name)"),
                                   subtitle: FS.tilde(cellar), paths: [cellar], lastUsed: FS.mtime(cellar), risk: .careful,
                                   reason: tr("没有其他包依赖它\(desc)。无法判断你是否还在用", "No other package depends on it\(desc). Can't tell whether you still use it"),
                                   action: .brewUninstall(name)))
        }
        return items
    }
}
