import SwiftUI

enum Pane: Hashable {
    case overview
    case category(Category)
    case log
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var pane: Pane? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                DiskBar(disk: store.disk)
                    .padding(.vertical, 6)
                    .selectionDisabled()

                NavigationLink(value: Pane.overview) {
                    Label("总览", systemImage: "gauge.with.dots.needle.67percent")
                }

                Section("分类") {
                    ForEach(Category.allCases) { c in
                        NavigationLink(value: Pane.category(c)) {
                            HStack {
                                Label(c.title, systemImage: c.icon)
                                Spacer()
                                if store.scanning.contains(c) {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text(formatBytes(store.total(c)))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink(value: Pane.log) {
                        Label("清理记录", systemImage: "list.bullet.rectangle")
                            .badge(store.log.count)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 250)
            .safeAreaInset(edge: .bottom) { TrashFooter().padding(10) }
        } detail: {
            switch pane {
            case .category(let c): CategoryView(category: c)
            case .log: LogView()
            default: OverviewView(open: { pane = .category($0) })
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await store.scan() } } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning || store.cleaning)
                .help("重新扫描 (⌘R)")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.selected.isEmpty || store.cleaning { CleanBar() }
        }
        .task { if store.lastScan == nil { await store.scan() } }
    }
}

struct DiskBar: View {
    let disk: DiskInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive")
                Text("系统磁盘").font(.headline)
                Spacer()
                Text("\(Int(disk.usedFraction * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: disk.usedFraction)
                .tint(disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.8 ? .orange : .accentColor)
            Text("可用 \(formatBytes(disk.free)) / 共 \(formatBytes(disk.total))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TrashFooter: View {
    @EnvironmentObject var store: Store
    @State private var confirm = false

    var body: some View {
        HStack {
            Image(systemName: "trash")
            VStack(alignment: .leading, spacing: 1) {
                Text("废纸篓").font(.callout)
                Text(store.trashSize.map { $0 == 0 ? "空的" : formatBytes($0) } ?? "需要完全磁盘访问权限才能读取")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("清倒") { confirm = true }
                .disabled(store.trashSize == 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .confirmationDialog("永久删除废纸篓里的所有项目？", isPresented: $confirm) {
            Button("清倒废纸篓", role: .destructive) { store.emptyTrash() }
        } message: {
            Text("这一步无法撤销。之前通过 MacSweep 移到废纸篓的东西也会一起永久删除。")
        }
    }
}

/// Shown at the bottom of every page while something is selected.
struct CleanBar: View {
    @EnvironmentObject var store: Store
    @State private var confirm = false

    var body: some View {
        HStack(spacing: 12) {
            if store.cleaning {
                ProgressView(value: Double(store.progress.done), total: Double(max(store.progress.total, 1)))
                    .frame(width: 160)
                Text("正在清理 \(store.progress.done)/\(store.progress.total)…")
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                Text("已选 \(store.selected.count) 项，共 \(formatBytes(store.selectedSize))")
                    .monospacedDigit()
                let risky = store.selectedItems.filter { $0.risk == .careful }.count
                if risky > 0 {
                    Label("含 \(risky) 项「谨慎」", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.callout)
                }
            }
            Spacer()
            Button("取消选择") { store.selected = [] }
                .disabled(store.cleaning)
            Button { confirm = true } label: {
                Label("移到废纸篓", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(store.cleaning || store.selected.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .confirmationDialog("清理 \(store.selected.count) 项（\(formatBytes(store.selectedSize))）？", isPresented: $confirm) {
            Button("移到废纸篓", role: .destructive) { Task { await store.cleanSelected() } }
        } message: {
            Text("文件会移到废纸篓，清倒前都能恢复。git worktree 和 brew 包会用 git / brew 自己的命令移除。App Store 安装的软件可能会要求输入管理员密码。")
        }
    }
}
