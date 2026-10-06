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
                DiskSummary(disk: store.disk)
                    .padding(.vertical, 8)
                    .selectionDisabled()

                NavigationLink(value: Pane.overview) {
                    SidebarRow(title: "总览",
                               icon: IconTile(symbol: "sparkles",
                                              gradient: LinearGradient(colors: [Color(red: 0.35, green: 0.6, blue: 1), Color(red: 0.6, green: 0.35, blue: 0.95)],
                                                                       startPoint: .top, endPoint: .bottom),
                                              size: 24))
                }

                Section("分类") {
                    ForEach(Category.allCases) { c in
                        NavigationLink(value: Pane.category(c)) {
                            SidebarRow(title: c.title, icon: IconTile(c, size: 24),
                                       value: store.scanning.contains(c) ? nil : store.total(c),
                                       loading: store.scanning.contains(c))
                        }
                    }
                }

                Section {
                    NavigationLink(value: Pane.log) {
                        SidebarRow(title: "清理记录",
                                   icon: IconTile(symbol: "clock.arrow.circlepath",
                                                  gradient: LinearGradient(colors: [.gray.opacity(0.7), .gray], startPoint: .top, endPoint: .bottom),
                                                  size: 24),
                                   badge: store.log.isEmpty ? nil : "\(store.log.count)")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 250)
            .safeAreaInset(edge: .bottom) { TrashFooter().padding(10) }
        } detail: {
            ZStack(alignment: .bottom) {
                switch pane {
                case .category(let c): CategoryView(category: c)
                case .log: LogView()
                default: OverviewView(open: { pane = .category($0) })
                }
                if !store.selected.isEmpty || store.cleaning {
                    CleanBar()
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: store.selected.isEmpty && !store.cleaning)
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
        .task { if store.lastScan == nil { await store.scan() } }
    }
}

struct SidebarRow<Icon: View>: View {
    let title: String
    let icon: Icon
    var value: Int64? = nil
    var loading = false
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(title)
            Spacer(minLength: 4)
            if loading {
                ProgressView().controlSize(.mini)
            } else if let value {
                Text(formatBytes(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if let badge {
                Text(badge).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

struct DiskSummary: View {
    let disk: DiskInfo

    private var tint: Color {
        disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.8 ? .orange : .accentColor
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: disk.usedFraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(disk.usedFraction * 100))")
                    .font(.rounded(11, .bold)).monospacedDigit()
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Macintosh HD").font(.callout.weight(.semibold))
                Text("可用 \(formatBytes(disk.free))").font(.caption).foregroundStyle(.secondary)
                Text("共 \(formatBytes(disk.total))").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

struct TrashFooter: View {
    @EnvironmentObject var store: Store
    @State private var confirm = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: store.trashSize == 0 ? "trash" : "trash.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("废纸篓").font(.callout.weight(.medium))
                Text(store.trashSize.map { $0 == 0 ? "空的" : formatBytes($0) } ?? "需要完全磁盘访问权限")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("清倒") { confirm = true }
                .controlSize(.small)
                .disabled(store.trashSize == 0)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .confirmationDialog("永久删除废纸篓里的所有项目？", isPresented: $confirm) {
            Button("清倒废纸篓", role: .destructive) { store.emptyTrash() }
        } message: {
            Text("这一步无法撤销。之前通过 MacSweep 移到废纸篓的东西也会一起永久删除。")
        }
    }
}

/// Floating capsule shown while something is selected or a clean is running.
struct CleanBar: View {
    @EnvironmentObject var store: Store
    @State private var confirm = false

    var body: some View {
        HStack(spacing: 14) {
            if store.cleaning {
                ProgressView(value: Double(store.progress.done), total: Double(max(store.progress.total, 1)))
                    .frame(width: 160)
                Text("正在清理 \(store.progress.done)/\(store.progress.total)…").monospacedDigit()
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("已选 \(store.selected.count) 项").font(.callout.weight(.semibold))
                    let risky = store.selectedItems.filter { $0.risk == .careful }.count
                    if risky > 0 {
                        Label("含 \(risky) 项「谨慎」", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    } else {
                        Text("全部可从废纸篓找回").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(formatBytes(store.selectedSize))
                    .font(.rounded(22, .bold)).monospacedDigit()
                    .contentTransition(.numericText())
                Button("取消") { store.selected = [] }
                    .buttonStyle(.borderless)
            }
            Button { confirm = true } label: {
                Label("清理", systemImage: "trash.fill")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .clipShape(Capsule())
            .disabled(store.cleaning || store.selected.isEmpty)
        }
        .padding(.leading, 22).padding(.trailing, 10).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .confirmationDialog("清理 \(store.selected.count) 项（\(formatBytes(store.selectedSize))）？", isPresented: $confirm) {
            Button("移到废纸篓", role: .destructive) { Task { await store.cleanSelected() } }
        } message: {
            Text("文件会移到废纸篓，清倒前都能恢复。git worktree 和 brew 包会用 git / brew 自己的命令移除。App Store 安装的软件可能会要求输入管理员密码。")
        }
    }
}
