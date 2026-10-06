# MacSweep

原生 SwiftUI 的 macOS 磁盘清理工具。所有删除都是移到废纸篓（可恢复），git worktree 和 Homebrew 包交给 git / brew 自己移除。

## 扫描什么

| 分类 | 内容 |
|---|---|
| 缓存与日志 | `~/Library/Caches`、`~/.cache`、`~/Library/Logs`、npm/pnpm/bun/cargo/go/gradle/NuGet 缓存、更新器残留的 `*.ShipIt` 安装包 |
| 卸载残留 | `~/Library` 下 11 个位置（Application Support、Containers、Group Containers、Caches、Preferences、HTTPStorages、WebKit、Saved Application State 等）里找不到所属软件的条目，按软件聚合 |
| 很少用的软件 | `/Applications`、`~/Applications` 里的第三方软件，按最后使用时间排序；卸载时连同它在 `~/Library` 的数据一起移除 |
| 大件可再下载 | macOS 航拍壁纸视频、Claude 虚拟机镜像、HuggingFace/Whisper/LM Studio/Ollama 模型、Docker 磁盘、下载文件夹里的安装包 |
| 开发垃圾 | 已合并且干净的 git worktree、编辑器扩展旧版本、Xcode DerivedData 等、Homebrew 缓存和叶子包、60 天没动过的 `node_modules` |

「卸载残留」的判断方式：收集所有已安装软件的 bundle ID（Spotlight 找到的全部 .app，包括 Steam 游戏，以及软件内的辅助程序、扩展、登录项），加上 PATH 里的命令行工具和 brew 包名，对不上的才算残留。按名称而不是 bundle ID 匹配的条目、含用户数据的条目，一律标成「需确认」；最近 14 天还有写入的标成「谨慎」。

## 构建

```bash
./scripts/build-app.sh --install   # 构建 dist/MacSweep.app 并装到 ~/Applications
.build/debug/MacSweep --dump       # 不开窗口，直接在终端打印扫描结果（需先 swift build）
```

只需要 Command Line Tools（Swift 6），不需要 Xcode。

## 权限

- **完全磁盘访问权限**：没有它时，MacSweep 会跳过其他软件的 Containers、废纸篓、下载、文稿，免得 macOS 反复弹窗。在「系统设置 › 隐私与安全性 › 完全磁盘访问权限」里打开 MacSweep，回到软件会自动重新扫描。
- **签名**：`scripts/setup-signing.sh` 会在独立钥匙串 `~/Library/Keychains/macsweep-signing.keychain-db` 里生成一张自签名证书（不碰登录钥匙串），`build-app.sh` 用它签名。签名身份固定，所以授权在重新编译后依然有效；临时签名（ad-hoc）每次编译都会变，macOS 会当成新软件、忘掉授权。
- **自动化（访达）**：App Store 安装的软件属于 root，普通移动会失败，这时交给访达处理，可能会要求输入管理员密码。
