import Foundation
import SwiftUI

/// The big slices of the disk, in the order the bar shows them.
enum Bucket: String, CaseIterable, Identifiable {
    case apps, personal, system, macos, hidden, free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "软件"
        case .personal: "个人文件"
        case .system: "系统数据"
        case .macos: "macOS 本身"
        case .hidden: "读不到的部分"
        case .free: "可用"
        }
    }

    var blurb: String {
        switch self {
        case .apps: "应用本体，加上它散落在资源库里的数据、缓存、沙盒容器，合在一起算"
        case .personal: "桌面、文稿、下载、照片、iCloud 云盘的本地副本、废纸篓"
        case .system: "系统下载的资源（Siri、翻译、字体）、临时文件、睡眠镜像、系统数据库"
        case .macos: "系统本体、启动数据、恢复系统、虚拟内存，只读或由系统管理，不能删"
        case .hidden: "Spotlight 索引、文件版本历史、APFS 快照、可清除空间等，只有系统能读"
        case .free: "还能用的空间"
        }
    }

    var colors: [Color] {
        switch self {
        case .apps: [Color(red: 1.00, green: 0.72, blue: 0.30), Color(red: 0.98, green: 0.47, blue: 0.16)]
        case .personal: [Color(red: 0.38, green: 0.70, blue: 1.00), Color(red: 0.13, green: 0.47, blue: 0.96)]
        case .system: [Color(red: 0.78, green: 0.52, blue: 1.00), Color(red: 0.53, green: 0.28, blue: 0.93)]
        case .macos: [Color(white: 0.62), Color(white: 0.48)]
        case .hidden: [Color(red: 1.00, green: 0.50, blue: 0.62), Color(red: 0.90, green: 0.24, blue: 0.44)]
        case .free: [Color.primary.opacity(0.07), Color.primary.opacity(0.07)]
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom) }
}

struct UsagePart: Identifiable, Hashable {
    let label: String
    let path: String?  // nil for things that are not a folder (APFS volumes, unreadable remainder)
    let size: Int64
    var id: String { (path ?? "") + "|" + label }
}

/// Who a chunk of disk belongs to: an app, a personal folder, or a piece of the system.
struct Owner: Identifiable {
    let id: String
    let name: String
    let bucket: Bucket
    var iconURL: URL? = nil
    var symbol: String = "app.fill"
    var note: String = ""
    var parts: [UsagePart] = []
    var total: Int64 { parts.reduce(0) { $0 + $1.size } }
}

struct SpaceReport {
    let root: SpaceNode
    let container: ContainerUsage
    let owners: [Owner]
    /// Display path -> owner name, so the folder browser can say whose a folder is.
    let ownerByPath: [String: String]
    let scannedFiles: Int
    let date: Date

    /// Owner of a folder, or of the nearest enclosing folder that has one.
    func owner(of node: SpaceNode) -> String? {
        var n: SpaceNode? = node
        while let cur = n {
            if let o = ownerByPath[cur.path] { return o }
            n = cur.parent
        }
        return nil
    }

    func total(_ b: Bucket) -> Int64 {
        b == .free ? container.free : owners.filter { $0.bucket == b }.reduce(0) { $0 + $1.total }
    }

    func owners(in buckets: Set<Bucket>) -> [Owner] {
        owners.filter { buckets.contains($0.bucket) && $0.total > 0 }.sorted { $0.total > $1.total }
    }
}

enum SpaceAnalysis {
    static func run(progress: SpaceScanner.Progress) -> SpaceReport {
        let fda = FS.hasFullDiskAccess()
        var skip = Set<String>()
        if !fda {
            let home = FS.home.path
            skip = Set(FS.promptingFolders.map { home + "/" + $0 } + [home + "/Library/Containers", home + "/Library/Group Containers"])
        }
        let root = SpaceScanner.scan(skip: skip, progress: progress)
        let container = ContainerUsage.read()
        let inv = AppInventory()
        var a = Attributor(root: root, inv: inv)
        a.run(container: container)
        let owners = a.owners.values.filter { $0.total > 0 }
        return SpaceReport(root: root, container: container, owners: owners, ownerByPath: a.ownerByPath,
                           scannedFiles: progress.value.files, date: Date())
    }
}

/// Hands every folder to exactly one owner. Specific rules run first; a later, broader claim
/// only gets what is left after the claims inside it.
struct Attributor {
    let root: SpaceNode
    let inv: AppInventory
    var owners: [String: Owner] = [:]
    var ownerByPath: [String: String] = [:]
    private var claims: [String: Int64] = [:] // path -> net size claimed

    init(root: SpaceNode, inv: AppInventory) {
        self.root = root
        self.inv = inv
    }

    private let home = FS.home.path

    // MARK: claiming

    private func ancestorClaimed(_ path: String) -> Bool {
        var p = path
        while let r = p.range(of: "/", options: .backwards), r.lowerBound > p.startIndex {
            p = String(p[..<r.lowerBound])
            if claims[p] != nil { return true }
        }
        return false
    }

    private func claimedBelow(_ path: String) -> Int64 {
        let prefix = path == "/" ? "/" : path + "/"
        return claims.reduce(0) { $1.key.hasPrefix(prefix) ? $0 + $1.value : $0 }
    }

    @discardableResult
    private mutating func claim(_ path: String, _ ownerID: String, _ label: String) -> Int64 {
        guard claims[path] == nil, !ancestorClaimed(path), let n = root.node(at: path), owners[ownerID] != nil else { return 0 }
        let s = n.size - claimedBelow(path)
        guard s > 0 else { return 0 }
        claims[path] = s
        owners[ownerID]!.parts.append(UsagePart(label: label, path: path, size: s))
        ownerByPath[path] = owners[ownerID]!.name
        return s
    }

    private mutating func pseudo(_ id: String, _ name: String, _ bucket: Bucket, symbol: String, note: String = "") -> String {
        if owners[id] == nil { owners[id] = Owner(id: id, name: name, bucket: bucket, symbol: symbol, note: note) }
        return id
    }

    /// Owners are keyed by app name, so an app and its nested or renamed copies add up together.
    private mutating func app(_ lid: String) -> String {
        let name = inv.appNameByID[lid] ?? lid
        let id = "app:" + AppInventory.normalize(name)
        let url = inv.appURLByID[lid]
        if owners[id] == nil {
            owners[id] = Owner(id: id, name: name, bucket: .apps, iconURL: url)
        } else if let url, url.path.hasPrefix("/Applications/"), owners[id]!.iconURL?.path.hasPrefix("/Applications/") != true {
            // Prefer the copy in /Applications for the name and icon people recognise.
            owners[id] = Owner(id: id, name: name, bucket: .apps, iconURL: url, parts: owners[id]!.parts)
        }
        return id
    }

    /// Folders named after a vendor ("Google", "Microsoft") or a tool's short name (".vscode").
    private static let aliases: [String: [String]] = [
        "vscode": ["com.microsoft.vscode"], "vscodeinsiders": ["com.microsoft.vscodeinsiders"],
        "google": ["com.google.chrome"], "chrome": ["com.google.chrome"],
        "microsoft": ["com.microsoft.word", "com.microsoft.excel", "com.microsoft.vscode"],
        "office": ["com.microsoft.word", "com.microsoft.excel"], "tencent": ["com.tencent.xinwechat", "com.tencent.qq"],
        "jetbrains": ["com.jetbrains.intellij", "com.jetbrains.pycharm"], "zoomus": ["us.zoom.xos"],
    ]

    private func alias(_ raw: String) -> String? {
        let n = AppInventory.normalize(raw)
        if let ids = Self.aliases[n], let id = ids.first(where: { inv.appNameByID[$0] != nil }) { return id }
        // ".antigravity" -> "Antigravity IDE"
        if n.count >= 5, let hit = inv.appIDByName.filter({ $0.key.hasPrefix(n) }).min(by: { $0.key.count < $1.key.count }) {
            return hit.value
        }
        return nil
    }

    /// App owning a ~/Library entry named after a bundle ID, group ID, team-prefixed ID or app name.
    private func appID(forKey raw: String) -> String? {
        var k = raw
        for suffix in [".savedState", ".plist", ".binarycookies"] where k.hasSuffix(suffix) { k = String(k.dropLast(suffix.count)) }
        if k.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) != nil { k = String(k.dropFirst(11)) }
        k = k.lowercased()
        if k.hasPrefix("group.") { k = String(k.dropFirst(6)) }
        if inv.appNameByID[k] != nil { return k }
        let ids = inv.appNameByID.keys
        if let id = ids.filter({ k.hasPrefix($0 + ".") }).max(by: { $0.count < $1.count }) { return id }
        if k.split(separator: ".").count >= 3, let id = ids.filter({ $0.hasPrefix(k + ".") }).min(by: { $0.count < $1.count }) { return id }
        if let id = alias(raw) { return id }
        return inv.appIDByName[AppInventory.normalize(k.split(separator: ".").count >= 3 ? String(k.split(separator: ".").last!) : k)]
    }

    private func appID(named name: String) -> String? { alias(name) ?? inv.appIDByName[AppInventory.normalize(name)] }

    // MARK: rules

    mutating func run(container: ContainerUsage) {
        claimApps()
        claimSpecials()
        claimLibrary()
        claimHome()
        claimSystem()
        claimVolumes(container)
    }

    private mutating func claimApps() {
        // Parents before the helper apps nested inside them.
        let apps = inv.appURLByID.filter { !$0.value.path.hasPrefix("/System/") }
            .sorted { $0.value.path.count < $1.value.path.count }
        for (lid, url) in apps { claim(url.path, app(lid), "应用本体") }
    }

    private mutating func claimSpecials() {
        let L = home + "/Library"
        let appRules: [(String, String, String)] = [
            (L + "/Messages", "com.apple.mobilesms", "聊天记录和附件"),
            (L + "/Mail", "com.apple.mail", "邮件和附件"),
            (L + "/Safari", "com.apple.safari", "书签、历史、阅读列表"),
            (L + "/Calendars", "com.apple.ical", "日历数据"),
            (home + "/Pictures/Photos Library.photoslibrary", "com.apple.photos", "照片图库"),
            (home + "/Music/Music", "com.apple.music", "音乐资料库"),
            (L + "/Application Support/AddressBook", "com.apple.addressbook", "通讯录"),
        ]
        for (path, lid, label) in appRules where inv.appNameByID[lid] != nil { claim(path, app(lid), label) }

        let xcode = inv.appNameByID["com.apple.dt.xcode"] != nil ? app("com.apple.dt.xcode")
            : pseudo("xcode", "Xcode 与模拟器", .apps, symbol: "hammer.fill")
        for (path, label) in [(L + "/Developer/CoreSimulator", "模拟器设备和数据"),
                              (L + "/Developer/Xcode", "编译缓存、设备支持文件"),
                              (L + "/Developer", "开发者数据"),
                              ("/Library/Developer", "命令行工具、模拟器镜像"),
                              ("/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime", "iOS 模拟器系统"),
                              ("/System/Library/AssetsV2/com_apple_MobileAsset_AppleDeveloperDocumentation", "开发者文档")] {
            claim(path, xcode, label)
        }
        for c in root.node(at: "/System/Library/AssetsV2")?.children ?? [] where c.name.contains("SimulatorRuntime") {
            claim(c.path, xcode, "模拟器系统")
        }

        let backups = pseudo("backup", "iPhone / iPad 备份", .personal, symbol: "iphone",
                             note: "用访达备份 iPhone 留下的；在 访达 › 你的手机 › 管理备份 里删旧的")
        claim(L + "/Application Support/MobileSync/Backup", backups, "设备备份")

        let brew = pseudo("brew", "Homebrew", .apps, symbol: "mug.fill", note: "brew 装的命令行软件；brew list 看看哪些不用了")
        for c in root.node(at: "/opt/homebrew/Cellar")?.children ?? [] { claim(c.path, brew, c.name) }
        for c in root.node(at: "/opt/homebrew/Caskroom")?.children ?? [] { claim(c.path, brew, c.name + "（cask）") }
        claim("/opt/homebrew", brew, "Homebrew 其他文件")
        claim("/usr/local/Homebrew", brew, "Homebrew（Intel）")
        claim("/usr/local/Cellar", brew, "Homebrew 软件（Intel）")
    }

    private mutating func claimLibrary() {
        let L = home + "/Library"
        let locations: [(String, String)] = [
            (L + "/Containers", "沙盒数据"), (L + "/Group Containers", "共享数据"),
            (L + "/Application Support", "应用支持数据"), (L + "/Caches", "缓存"),
            (L + "/HTTPStorages", "网络缓存"), (L + "/WebKit", "网页数据"),
            (L + "/Saved Application State", "窗口状态"), (L + "/Logs", "日志"),
            (L + "/Application Scripts", "脚本"), (L + "/Preferences", "设置"), (L + "/Cookies", "Cookie"),
            ("/Library/Application Support", "全局支持数据"), ("/Library/Caches", "全局缓存"), ("/Library/Logs", "全局日志"),
        ]
        let apple = pseudo("apple-services", "macOS 自带服务的数据", .system, symbol: "applelogo",
                           note: "照片分析、Siri、Spotlight 等系统后台服务在资源库里的数据")
        let misc = pseudo("misc-apps", "其他零散软件数据", .apps, symbol: "square.grid.3x3.fill",
                          note: "很多小软件各自留下的一点点数据")
        for (dir, label) in locations {
            for c in root.node(at: dir)?.children ?? [] {
                if let lid = appID(forKey: c.name) {
                    claim(c.path, app(lid), label)
                } else if c.name.lowercased().hasPrefix("com.apple.") || c.name.hasPrefix("group.com.apple.") {
                    claim(c.path, apple, label + "：" + c.name)
                } else if c.size >= 50 << 20 {
                    let id = pseudo("unknown:" + c.name.lowercased(), c.name, .apps, symbol: "questionmark.app.dashed",
                                    note: "找不到对应的已安装软件，可能已经卸载了；看看「卸载残留」")
                    claim(c.path, id, label)
                } else {
                    claim(c.path, misc, label + "：" + c.name)
                }
            }
        }
    }

    private mutating func claimHome() {
        let tools: [String: (String, String)] = [
            ".npm": ("Node.js / npm", "shippingbox.fill"), ".nvm": ("Node.js / npm", "shippingbox.fill"),
            ".bun": ("Node.js / npm", "shippingbox.fill"), ".pnpm-store": ("Node.js / npm", "shippingbox.fill"),
            ".cargo": ("Rust", "gearshape.2.fill"), ".rustup": ("Rust", "gearshape.2.fill"),
            ".gradle": ("Java / Gradle", "cup.and.saucer.fill"), ".m2": ("Java / Gradle", "cup.and.saucer.fill"),
            ".cache": ("命令行工具缓存", "archivebox.fill"), ".local": ("命令行工具", "terminal.fill"),
            ".conda": ("Python / Conda", "chevron.left.forwardslash.chevron.right"),
            ".pyenv": ("Python / Conda", "chevron.left.forwardslash.chevron.right"),
            ".ollama": ("Ollama", "cpu.fill"), ".lmstudio": ("LM Studio", "cpu.fill"), ".docker": ("Docker", "shippingbox.fill"),
        ]
        let personal: [String: (String, String)] = [
            "Desktop": ("桌面", "menubar.dock.rectangle"), "Documents": ("文稿", "doc.fill"),
            "Downloads": ("下载", "arrow.down.circle.fill"), "Pictures": ("图片", "photo.fill"),
            "Movies": ("影片", "film.fill"), "Music": ("音乐", "music.note"), ".Trash": ("废纸篓", "trash.fill"),
        ]

        let icloud = pseudo("icloud", "iCloud 云盘", .personal, symbol: "icloud.fill",
                            note: "下载到本机的 iCloud 文件；在访达里右键「移除下载项」可以只留在云端")
        claim(home + "/Library/Mobile Documents", icloud, "本地副本")

        let cli = pseudo("cli", "其他命令行工具数据", .apps, symbol: "terminal.fill")
        for c in root.node(at: home)?.children ?? [] {
            if let (name, symbol) = personal[c.name] {
                claim(c.path, pseudo("home:" + c.name, name, .personal, symbol: symbol), name)
            } else if c.name == "Library" {
                continue
            } else if c.name.hasPrefix(".") {
                if let (name, symbol) = tools[c.name] {
                    claim(c.path, pseudo("tool:" + name, name, .apps, symbol: symbol), "~/" + c.name)
                } else if let lid = appID(named: String(c.name.dropFirst())) {
                    claim(c.path, app(lid), "~/" + c.name)
                } else {
                    claim(c.path, cli, "~/" + c.name)
                }
            } else {
                claim(c.path, pseudo("home:" + c.name, c.name, .personal, symbol: "folder.fill"), "~/" + c.name)
            }
        }

        let lib = pseudo("library-rest", "资源库里的其他数据", .system, symbol: "books.vertical.fill",
                         note: "~/Library 里不属于某个软件的部分：键盘词库、字体、邮件下载等")
        for c in root.node(at: home + "/Library")?.children ?? [] { claim(c.path, lib, c.name) }
        claim(home + "/Library", lib, "零散文件")
        claim(home, pseudo("home:files", "个人文件夹里的零散文件", .personal, symbol: "doc.on.doc.fill"), "~")
        for c in root.node(at: "/Users")?.children ?? [] {
            claim(c.path, pseudo("users", "共享文件夹和其他用户", .personal, symbol: "person.2.fill"), c.name)
        }
    }

    private mutating func claimSystem() {
        let assetNames: [(String, String)] = [
            ("Siri", "Siri"), ("Translation", "翻译"), ("Font", "字体"), ("Speech", "语音识别"),
            ("TextToSpeech", "朗读语音"), ("Linguistic", "语言数据"), ("Photos", "照片智能功能"),
            ("Dictionary", "词典"), ("Keyboard", "键盘"), ("GenerativeModels", "Apple 智能模型"), ("MLModels", "机器学习模型"),
        ]
        let assets = pseudo("assets", "系统下载的资源", .system, symbol: "arrow.down.app.fill",
                            note: "Siri、翻译、字体、Apple 智能等按需下载的组件；关掉对应功能后系统会慢慢收回")
        for c in root.node(at: "/System/Library/AssetsV2")?.children ?? [] {
            let label = assetNames.first { c.name.contains($0.0) }?.1
                ?? c.name.replacingOccurrences(of: "com_apple_MobileAsset_", with: "")
            claim(c.path, assets, label)
        }

        let rules: [(String, String, String, String, String)] = [
            ("/private/var/folders", "tmp", "临时文件和缓存", "clock.arrow.circlepath", "系统和各软件的临时文件，重启或长时间不用会自动清掉一部分"),
            ("/private/var/vm", "vm", "睡眠镜像和交换文件", "memorychip.fill", "内存不够时写到硬盘上的部分，以及合盖睡眠时的内存镜像；重启后会变小"),
            ("/private/var/db", "db", "系统数据库", "cylinder.split.1x2.fill", "Spotlight、诊断、软件更新等系统数据库"),
            ("/Library", "library", "全局资源库", "books.vertical.fill", "给所有用户用的驱动、插件、字体、音频素材等"),
            ("/MobileSoftwareUpdate", "update", "系统更新文件", "arrow.triangle.2.circlepath", "下载好还没装、或装完没清的系统更新"),
            ("/.PreviousSystemInformation", "update", "系统更新文件", "arrow.triangle.2.circlepath", ""),
            ("/usr", "usr", "命令行底层文件", "terminal.fill", ""),
            ("/private", "private", "其他系统文件", "gearshape.2.fill", ""),
        ]
        for (path, id, name, symbol, note) in rules {
            let o = pseudo("sys:" + id, name, .system, symbol: symbol, note: note)
            if path == "/Library" {
                for c in root.node(at: path)?.children ?? [] { claim(c.path, o, c.name) }
            }
            claim(path, o, path)
        }
        let rest = pseudo("sys:rest", "其他", .system, symbol: "ellipsis.circle.fill")
        for c in root.children { claim(c.path, rest, c.path) }
    }

    private mutating func claimVolumes(_ c: ContainerUsage) {
        let names: [String: (String, String, String)] = [
            "System": ("macOS 系统本体", "applelogo", "只读、加密签名的系统卷，不能删"),
            "Preboot": ("启动和更新数据", "power", "开机需要的文件和系统更新用的组件"),
            "Recovery": ("恢复系统", "lifepreserver.fill", "按住电源键进入的恢复模式"),
            "VM": ("虚拟内存", "memorychip.fill", "内存不够用时暂存在硬盘的内容；开的软件越多越大，重启后变小"),
        ]
        for v in c.volumes where v.role != "Data" {
            let (name, symbol, note) = names[v.role] ?? (v.name, "internaldrive.fill", "")
            let id = "vol:" + v.role + v.name
            owners[id] = Owner(id: id, name: name, bucket: .macos, symbol: symbol, note: note,
                               parts: [UsagePart(label: "APFS 卷「\(v.name)」", path: nil, size: v.used)])
        }
        let unseen = c.used(role: "Data") - claims.values.reduce(0, +)
        if unseen > 0 {
            owners["hidden"] = Owner(id: "hidden", name: "macOS 不让读的部分", bucket: .hidden, symbol: "eye.slash.fill",
                                     note: "数据卷里扫不到的部分：Spotlight 索引、文件版本历史、文件系统日志、APFS 快照、可清除空间，以及其他只有 root 能读的文件",
                                     parts: [UsagePart(label: "数据卷已用 − 扫到的总和", path: nil, size: unseen)])
        }
    }
}
