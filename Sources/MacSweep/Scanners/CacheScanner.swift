import Foundation

/// Regenerable caches and logs. Paths already listed as orphans are skipped.
struct CacheScanner {
    let inv: AppInventory
    let claimed: Set<String>

    /// ~/.cache entries that are really models, handled by LargeScanner.
    static let modelCaches: Set<String> = ["huggingface", "whisper", "torch", "lm-studio", "ollama"]

    func scan() async -> [SweepItem] {
        var items: [SweepItem] = []

        func add(_ url: URL, title: String, risk: Risk, reason: String) {
            guard !claimed.contains(url.path), FS.exists(url) else { return }
            items.append(SweepItem(id: "cache:\(url.path)", category: .caches, title: title,
                                   subtitle: FS.tilde(url), paths: [url], lastUsed: FS.mtime(url),
                                   risk: risk, reason: reason, iconURL: inv.appURL(forID: url.lastPathComponent)))
        }

        for c in FS.children(FS.library.appendingPathComponent("Caches")) {
            let raw = c.lastPathComponent
            let lower = raw.lowercased()
            let name = inv.appName(forID: raw) ?? raw
            if lower.hasSuffix(".shipit") || lower.contains("updater") || lower.hasSuffix("-updater") {
                add(c, title: name, risk: .safe, reason: "软件自动更新下载的安装包残留")
            } else if lower.hasPrefix("com.apple.") {
                add(c, title: name, risk: .review, reason: "系统缓存，会自动重建，但相关功能首次使用会变慢")
            } else if lower == "ccache" {
                add(c, title: name, risk: .review, reason: "C/C++ 编译缓存；删除后下次全量编译会变慢")
            } else {
                add(c, title: name, risk: .safe, reason: "应用缓存，删除后按需自动重建")
            }
        }

        for c in FS.children(FS.url(".cache")) where !Self.modelCaches.contains(c.lastPathComponent) {
            add(c, title: "~/.cache/\(c.lastPathComponent)", risk: .safe, reason: "命令行工具缓存，按需重新下载/生成")
        }

        for c in FS.children(FS.library.appendingPathComponent("Logs")) {
            add(c, title: "日志：\(c.lastPathComponent)", risk: .safe, reason: "运行日志和崩溃报告")
        }

        let toolCaches: [(String, String)] = [
            (".npm/_cacache", "npm 下载缓存"),
            (".npm/_npx", "npx 临时安装的包"),
            ("Library/pnpm/store", "pnpm 包仓库"),
            (".bun/install/cache", "bun 下载缓存"),
            (".gradle/caches", "Gradle 依赖缓存"),
            (".cargo/registry", "Cargo crate 下载缓存"),
            (".nuget/packages", "NuGet 包缓存"),
            (".cocoapods/repos", "CocoaPods spec 仓库"),
            ("go/pkg/mod", "Go 模块缓存"),
        ]
        for (rel, reason) in toolCaches {
            add(FS.url(rel), title: "~/" + rel, risk: .safe, reason: reason + "，按需重新下载")
        }

        return await FS.sized(items, min: 1 << 20)
    }
}
