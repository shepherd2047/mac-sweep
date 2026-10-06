import Foundation

/// Big things that can be downloaded again.
struct LargeScanner {
    private static let known: [(String, String, Risk, String)] = [
        ("Library/Application Support/com.apple.wallpaper/aerials/videos", tr("macOS 航拍动态壁纸视频", "macOS aerial wallpaper videos"), .safe,
         tr("系统壁纸/屏保视频缓存，用到时会重新下载", "Wallpaper/screensaver video cache; re-downloaded when needed")),
        ("Library/Application Support/Claude/vm_bundles", tr("Claude 桌面版虚拟机镜像", "Claude desktop VM images"), .review,
         tr("Cowork/VM 功能用的系统镜像，下次使用会重新下载", "System images for Cowork/VM; re-downloaded on next use")),
        (".cache/huggingface", tr("HuggingFace 模型缓存", "HuggingFace model cache"), .review, tr("下载过的模型和数据集，用到时会重新下载", "Downloaded models and datasets; re-downloaded when needed")),
        (".cache/whisper", tr("Whisper 语音模型", "Whisper speech models"), .review, tr("openai-whisper 下载的模型", "Models downloaded by openai-whisper")),
        (".cache/torch", tr("PyTorch 模型缓存", "PyTorch model cache"), .review, tr("torch hub 下载的权重", "Weights downloaded by torch hub")),
        (".cache/lm-studio", tr("LM Studio 缓存", "LM Studio cache"), .review, tr("LM Studio 的下载缓存", "LM Studio download cache")),
        (".lmstudio/models", tr("LM Studio 模型", "LM Studio models"), .review, tr("本地大模型，需要时可在 LM Studio 里重新下载", "Local LLMs; re-download in LM Studio when needed")),
        (".ollama/models", tr("Ollama 模型", "Ollama models"), .review, tr("本地大模型，可用 ollama pull 重新下载", "Local LLMs; re-download with ollama pull")),
        ("Library/Containers/com.docker.docker/Data/vms", tr("Docker 虚拟磁盘", "Docker virtual disk"), .careful,
         tr("包含所有镜像和容器；删除等于清空 Docker", "Holds all images and containers; deleting it wipes Docker")),
        ("Library/Application Support/MobileSync/Backup", tr("iPhone/iPad 本地备份", "iPhone/iPad local backups"), .careful,
         tr("设备备份，删除前确认 iCloud 或其他地方有备份", "Device backups; make sure you have a copy in iCloud or elsewhere first")),
        ("Library/Containers/com.apple.Music/Data/Library/Caches", tr("Apple Music 缓存", "Apple Music cache"), .safe, tr("流媒体缓存", "Streaming cache")),
        ("Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache", tr("播客缓存", "Podcasts cache"), .safe, tr("下载的播客单集", "Downloaded podcast episodes")),
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
                                   reason: isInstaller ? tr("下载文件夹里的安装包，装完一般就没用了", "Installer in Downloads; usually not needed after installing") : tr("下载文件夹里的压缩包，确认已解压/不需要", "Archive in Downloads; check it's extracted or not needed")))
        }
        return await FS.sized(items, min: 20 << 20)
    }
}
