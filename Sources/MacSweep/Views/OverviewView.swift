import SwiftUI

struct OverviewView: View {
    let open: (Category) -> Void
    @EnvironmentObject var store: Store

    private var grandTotal: Int64 { Category.allCases.reduce(0) { $0 + store.total($1) } }
    private var safeTotal: Int64 { Category.allCases.reduce(0) { $0 + store.safeTotal($1) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if !store.hasFullDiskAccess { FDABanner() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(Category.allCases) { c in
                        CategoryCard(category: c) { open(c) }
                    }
                }
                tips
            }
            .padding(24)
        }
        .navigationTitle("总览")
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 28) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: store.disk.usedFraction)
                    .stroke(store.disk.usedFraction > 0.9 ? Color.red : .accentColor,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(formatBytes(store.disk.free)).font(.title2.bold().monospacedDigit())
                    Text("可用").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 130, height: 130)

            VStack(alignment: .leading, spacing: 8) {
                if store.isScanning {
                    HStack { ProgressView().controlSize(.small); Text("正在扫描…").font(.title3) }
                } else {
                    Text("找到 \(formatBytes(grandTotal)) 可清理").font(.title.bold())
                }
                Text("其中 \(formatBytes(safeTotal)) 标记为「安全」：缓存、更新残留、已合并的 worktree 这类删了会自动重建或可随时重新下载的东西。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button {
                        store.selectSafe()
                    } label: {
                        Label("选中所有安全项", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isScanning || safeTotal == 0)
                    if let d = store.lastScan {
                        Text("上次扫描：\(d.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("说明").font(.headline)
            Group {
                Text("• 「安全」：会自动重建或随时可再下载。「需确认」：可能有你要的数据或设置。「谨慎」：可能还在用，或有未保存的工作。")
                Text("• 所有文件都是移到废纸篓，清倒之前都能找回；空间要清倒废纸篓后才真正释放。")
                Text("• 「卸载残留」通过对照所有已安装的软件（含 Steam 游戏、软件内的辅助程序和扩展、命令行工具）来判断，名称对不上的会标成「需确认」。")
            }
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CategoryCard: View {
    let category: Category
    let action: () -> Void
    @EnvironmentObject var store: Store

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: category.icon).font(.title2).foregroundStyle(.tint)
                    Spacer()
                    if store.scanning.contains(category) { ProgressView().controlSize(.small) }
                }
                Text(category.title).font(.headline)
                Text(formatBytes(store.total(category))).font(.title.bold().monospacedDigit())
                HStack(spacing: 10) {
                    Text("\(store.items(category).count) 项").foregroundStyle(.secondary)
                    if store.safeTotal(category) > 0 {
                        Text("安全 \(formatBytes(store.safeTotal(category)))").foregroundStyle(.green)
                    }
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct LogView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            if store.log.isEmpty {
                ContentUnavailableView("还没有清理记录", systemImage: "list.bullet.rectangle")
            } else {
                List(store.log) { e in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: e.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(e.ok ? .green : .red)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(e.title).bold()
                                Spacer()
                                if e.freed > 0 { Text(formatBytes(e.freed)).monospacedDigit().foregroundStyle(.secondary) }
                                Text(e.date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.tertiary)
                            }
                            if !e.detail.isEmpty {
                                Text(e.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle("清理记录")
    }
}
