import Foundation

/// Big things that can be downloaded again.
struct LargeScanner {
    private static let known: [(String, String, Risk, String)] = [
        ("Library/Application Support/com.apple.wallpaper/aerials/videos", "macOS 航拍动态壁纸视频", .safe,
         "系统壁纸/屏保视频缓存，用到时会重新下载"),
        ("Library/Application Support/Claude/vm_bundles", "Claude 桌面版虚拟机镜像", .review,
         "Cowork/VM 功能用的系统镜像，下次使用会重新下载"),
        (".cache/huggingface", "HuggingFace 模型缓存", .review, "下载过的模型和数据集，用到时会重新下载"),
        (".cache/whisper", "Whisper 语音模型", .review, "openai-whisper 下载的模型"),
        (".cache/torch", "PyTorch 模型缓存", .review, "torch hub 下载的权重"),
        (".cache/lm-studio", "LM Studio 缓存", .review, "LM Studio 的下载缓存"),
        (".lmstudio/models", "LM Studio 模型", .review, "本地大模型，需要时可在 LM Studio 里重新下载"),
        (".ollama/models", "Ollama 模型", .review, "本地大模型，可用 ollama pull 重新下载"),
        ("Library/Containers/com.docker.docker/Data/vms", "Docker 虚拟磁盘", .careful,
         "包含所有镜像和容器；删除等于清空 Docker"),
        ("Library/Application Support/MobileSync/Backup", "iPhone/iPad 本地备份", .careful,
         "设备备份，删除前确认 iCloud 或其他地方有备份"),
        ("Library/Containers/com.apple.Music/Data/Library/Caches", "Apple Music 缓存", .safe, "流媒体缓存"),
        ("Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache", "播客缓存", .safe, "下载的播客单集"),
    ]

    private static let installerExts: Set<String> = ["dmg", "pkg", "iso", "xip", "zip", "rar", "7z", "msi", "exe", "ipsw"]

    func scan() async -> [SweepItem] {
        let fda = FS.hasFullDiskAccess()
        var items: [SweepItem] = Self.known.compactMap { rel, title, risk, reason in
            if !fda && rel.contains("Containers/") { return nil }
            let url = FS.url(rel)
            guard FS.exists(url) else { return nil }
            return SweepItem(id: "large:\(url.path)", category: .large, title: title, subtitle: "~/" + rel,
                             paths: [url], lastUsed: FS.mtime(url), risk: risk, reason: reason)
        }

        // Installers and archives sitting in Downloads.
        let downloads = FS.url("Downloads")
        for f in (FS.mayRead(downloads) ? FS.children(downloads) : []) where Self.installerExts.contains(f.pathExtension.lowercased()) {
            let m = FS.mtime(f)
            let days = m.map { Int(Date().timeIntervalSince($0) / 86400) } ?? 0
            let isInstaller = ["dmg", "pkg", "xip", "ipsw", "msi", "exe"].contains(f.pathExtension.lowercased())
            items.append(SweepItem(id: "large:\(f.path)", category: .large, title: f.lastPathComponent,
                                   subtitle: FS.tilde(f), paths: [f], lastUsed: m,
                                   risk: isInstaller && days > 7 ? .safe : .review,
                                   reason: isInstaller ? "下载文件夹里的安装包，装完一般就没用了" : "下载文件夹里的压缩包，确认已解压/不需要"))
        }
        return await FS.sized(items, min: 20 << 20)
    }
}
