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
                add(c, title: name, risk: .safe, reason: tr("软件自动更新下载的安装包残留", "Leftover installers from app auto-updates"))
            } else if lower.hasPrefix("com.apple.") {
                add(c, title: name, risk: .review, reason: tr("系统缓存，会自动重建，但相关功能首次使用会变慢", "System cache; rebuilt automatically, but related features are slower on first use"))
            } else if lower == "ccache" {
                add(c, title: name, risk: .review, reason: tr("C/C++ 编译缓存；删除后下次全量编译会变慢", "C/C++ compiler cache; the next full build will be slower"))
            } else {
                add(c, title: name, risk: .safe, reason: tr("应用缓存，删除后按需自动重建", "App cache; rebuilt automatically as needed"))
            }
        }

        for c in FS.children(FS.url(".cache")) where !Self.modelCaches.contains(c.lastPathComponent) {
            add(c, title: "~/.cache/\(c.lastPathComponent)", risk: .safe, reason: tr("命令行工具缓存，按需重新下载/生成", "CLI tool cache; re-downloaded or regenerated as needed"))
        }

        for c in FS.children(FS.library.appendingPathComponent("Logs")) {
            add(c, title: tr("日志：\(c.lastPathComponent)", "Logs: \(c.lastPathComponent)"), risk: .safe, reason: tr("运行日志和崩溃报告", "Runtime logs and crash reports"))
        }

        let toolCaches: [(String, String)] = [
            (".npm/_cacache", tr("npm 下载缓存", "npm download cache")),
            (".npm/_npx", tr("npx 临时安装的包", "Packages temporarily installed by npx")),
            ("Library/pnpm/store", tr("pnpm 包仓库", "pnpm package store")),
            (".bun/install/cache", tr("bun 下载缓存", "bun download cache")),
            (".gradle/caches", tr("Gradle 依赖缓存", "Gradle dependency cache")),
            (".cargo/registry", tr("Cargo crate 下载缓存", "Cargo crate download cache")),
            (".nuget/packages", tr("NuGet 包缓存", "NuGet package cache")),
            (".cocoapods/repos", tr("CocoaPods spec 仓库", "CocoaPods spec repos")),
            ("go/pkg/mod", tr("Go 模块缓存", "Go module cache")),
        ]
        for (rel, reason) in toolCaches {
            add(FS.url(rel), title: "~/" + rel, risk: .safe, reason: reason + tr("，按需重新下载", "; re-downloaded as needed"))
        }

        return await FS.sized(items, min: 1 << 20)
    }
}
