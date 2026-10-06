import Foundation
import SwiftUI

enum Category: String, CaseIterable, Identifiable, Hashable {
    case caches, orphans, apps, large, dev

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: "缓存与日志"
        case .orphans: "卸载残留"
        case .apps: "很少用的软件"
        case .large: "大件可再下载"
        case .dev: "开发垃圾"
        }
    }

    var icon: String {
        switch self {
        case .caches: "archivebox"
        case .orphans: "questionmark.folder"
        case .apps: "app.dashed"
        case .large: "externaldrive"
        case .dev: "hammer"
        }
    }

    var blurb: String {
        switch self {
        case .caches: "应用缓存、更新器残留安装包、日志。删除后会按需自动重建。"
        case .orphans: "软件被拖进废纸篓后，macOS 不会清理它在 ~/Library 里留下的数据。这里列出找不到对应已安装软件的文件夹。"
        case .apps: "按最后使用时间排序的第三方软件。卸载时会连同它在 ~/Library 里的数据一起移到废纸篓。"
        case .large: "体积大、但可以重新下载的东西：系统动态壁纸视频、AI 模型、虚拟机镜像、下载文件夹里的安装包。"
        case .dev: "已合并且干净的 git worktree、编辑器扩展旧版本、Xcode 缓存、Homebrew 缓存和叶子包、久未动过的 node_modules。"
        }
    }
}

enum Risk: Int, Comparable, CaseIterable, Hashable {
    case safe, review, careful

    static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .safe: "安全"
        case .review: "需确认"
        case .careful: "谨慎"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .careful: .red
        }
    }
}

enum CleanAction: Hashable {
    /// Move every path in the item to the Trash.
    case trash
    /// `git worktree remove` then delete the branch if it is merged.
    case gitWorktree(repo: URL, branch: String?)
    /// `brew uninstall <name>` then `brew autoremove`.
    case brewUninstall(String)
    /// `brew cleanup -s --prune=all`.
    case brewCleanup
}

struct SweepItem: Identifiable, Hashable {
    let id: String
    let category: Category
    var title: String
    var subtitle: String
    var paths: [URL]
    var size: Int64 = 0
    var lastUsed: Date? = nil
    var risk: Risk
    var reason: String
    var action: CleanAction = .trash
    /// File whose Finder icon represents the item (an app bundle, usually).
    var iconURL: URL? = nil

    var lastUsedSort: Date { lastUsed ?? .distantPast }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let ok: Bool
    let title: String
    let detail: String
    let freed: Int64
}

struct DiskInfo {
    var total: Int64 = 0
    var free: Int64 = 0
    var used: Int64 { total - free }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let free = v?.volumeAvailableCapacityForImportantUsage ?? Int64(v?.volumeAvailableCapacity ?? 0)
        return DiskInfo(total: Int64(v?.volumeTotalCapacity ?? 0), free: free)
    }
}

func formatBytes(_ n: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowsNonnumericFormatting = false // "0 KB", not "Zero KB"
    return f.string(fromByteCount: n)
}

func formatAge(_ d: Date?) -> String {
    guard let d else { return "无记录" }
    let days = Int(Date().timeIntervalSince(d) / 86400)
    switch days {
    case ..<1: return "今天"
    case ..<2: return "昨天"
    case ..<31: return "\(days) 天前"
    case ..<365: return "\(days / 30) 个月前"
    default: return String(format: "%.1f 年前", Double(days) / 365)
    }
}
