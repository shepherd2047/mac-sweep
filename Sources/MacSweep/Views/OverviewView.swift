import SwiftUI

struct OverviewView: View {
    let open: (Category) -> Void
    let openSpace: () -> Void
    @EnvironmentObject var store: Store

    private var grandTotal: Int64 { Category.allCases.reduce(0) { $0 + store.total($1) } }
    private var safeTotal: Int64 { Category.allCases.reduce(0) { $0 + store.safeTotal($1) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if !store.hasFullDiskAccess { FDABanner() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                    ForEach(Category.allCases) { c in
                        CategoryCard(category: c) { open(c) }
                    }
                }
                tips
            }
            .padding(28)
            .padding(.bottom, 70)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(tr("总览", "Overview"))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.isScanning ? tr("正在扫描…", "Scanning…") : tr("可以释放", "You can free up"))
                        .font(.headline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(formatBytes(grandTotal))
                            .font(.rounded(52, .heavy))
                            .foregroundStyle(LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 1), Color(red: 0.62, green: 0.32, blue: 0.95)],
                                                            startPoint: .leading, endPoint: .trailing))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if store.isScanning { ProgressView().controlSize(.small) }
                    }
                    Text(tr("其中 \(formatBytes(safeTotal)) 是「安全」项：缓存、更新残留、已合并的 worktree，删了会自动重建或随时能再下载。", "\(formatBytes(safeTotal)) of it is Safe: caches, updater leftovers and merged worktrees that rebuild themselves or can be downloaded again."))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 24)
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        store.selectSafe()
                    } label: {
                        Label(tr("选中所有安全项", "Select All Safe"), systemImage: "checkmark.seal.fill")
                            .padding(.horizontal, 6).padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isScanning || safeTotal == 0)
                    if let d = store.lastScan {
                        Text(tr("上次扫描 \(d.formatted(date: .omitted, time: .shortened))", "Last scan \(d.formatted(date: .omitted, time: .shortened))"))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }

            StorageBreakdown()
            Button(action: openSpace) {
                Label(tr("「其他已用」里到底是什么？按软件看每一 GB 花在哪", "What is all that \"Other\"? See where every GB goes, app by app"), systemImage: "chart.pie.fill")
            }
            .buttonStyle(.link)
        }
        .padding(24)
        .card(radius: 18)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("风险等级", "Risk levels")).font(.headline)
            HStack(alignment: .top, spacing: 14) {
                TipCard(risk: .safe, text: tr("会自动重建，或随时可以重新下载。", "Rebuilt automatically, or can be downloaded again anytime."))
                TipCard(risk: .review, text: tr("可能有你要的数据或设置，看一眼再删。", "May hold data or settings you want. Take a look first."))
                TipCard(risk: .careful, text: tr("可能还在用，或有没保存的工作。", "May still be in use, or hold unsaved work."))
            }
            Label(tr("所有东西都是移到废纸篓，清倒之前都能找回。", "Everything goes to the Trash and can be restored until you empty it."), systemImage: "arrow.uturn.backward.circle")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

/// Whole-disk bar: other used space, cleanable space per category, free space.
struct StorageBreakdown: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let disk = store.disk
        let total = Double(max(disk.total, 1))
        let cleanable = Category.allCases.map { ($0, store.total($0)) }
        let cleanSum = cleanable.reduce(Int64(0)) { $0 + $1.1 }
        let other = max(disk.used - cleanSum, 0)

        VStack(alignment: .leading, spacing: 12) {
            SegmentBar(segments:
                [.init(id: "other", value: Double(other) / total, fill: AnyShapeStyle(Color.primary.opacity(0.28)))]
                + cleanable.map { .init(id: $0.0.rawValue, value: Double($0.1) / total, fill: AnyShapeStyle($0.0.gradient)) }
                + [.init(id: "free", value: Double(disk.free) / total, fill: AnyShapeStyle(Color.primary.opacity(0.07)))],
                height: 18)

            // A grid rather than an HStack: seven fixed-width legends in one row would raise the
            // window's minimum width.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 6) {
                LegendDot(color: AnyShapeStyle(Color.primary.opacity(0.28)), title: tr("其他已用", "Other used"), value: other)
                ForEach(cleanable, id: \.0) { c, v in
                    LegendDot(color: AnyShapeStyle(c.gradient), title: c.title, value: v)
                }
                LegendDot(color: AnyShapeStyle(Color.primary.opacity(0.07)), title: tr("可用", "Free"), value: disk.free)
            }
            .font(.caption)
        }
    }
}

struct LegendDot: View {
    let color: AnyShapeStyle
    let title: String
    let value: Int64

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            Text(title).foregroundStyle(.secondary)
            Text(formatBytes(value)).monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize()
    }
}

struct TipCard: View {
    let risk: Risk
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RiskBadge(risk: risk)
            Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .card(radius: 12)
    }
}

struct CategoryCard: View {
    let category: Category
    let action: () -> Void
    @EnvironmentObject var store: Store
    @State private var hover = false

    var body: some View {
        let total = store.total(category)
        let safe = store.safeTotal(category)

        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    IconTile(category, size: 40)
                    Spacer()
                    if store.scanning.contains(category) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.headline)
                    Text(formatBytes(total))
                        .font(.rounded(30))
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color.primary.opacity(0.07)).frame(height: 6)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(category.gradient)
                                    .frame(width: total > 0 ? max(6, g.size.width * CGFloat(Double(safe) / Double(total))) : 0)
                            }
                        }
                    HStack {
                        Text(tr("\(store.items(category).count) 项", "\(store.items(category).count) items"))
                        Spacer()
                        Text(safe > 0 ? tr("安全 \(formatBytes(safe))", "Safe \(formatBytes(safe))") : tr("无安全项", "Nothing safe"))
                            .foregroundStyle(safe > 0 ? category.tint : Color.secondary)
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .card(radius: 16)
            .scaleEffect(hover ? 1.015 : 1)
            .animation(.spring(duration: 0.25), value: hover)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct LogView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            if store.log.isEmpty {
                ContentUnavailableView(tr("还没有清理记录", "Nothing cleaned yet"), systemImage: "list.bullet.rectangle",
                                       description: Text(tr("清理过的项目会记在这里", "Cleaned items show up here")))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.log.enumerated()), id: \.element.id) { i, e in
                            if i > 0 { Divider().padding(.leading, 50) }
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: e.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .font(.title3)
                                    .foregroundStyle(e.ok ? .green : .red)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(e.title).font(.body.weight(.medium))
                                        Spacer()
                                        if e.freed > 0 {
                                            Text(formatBytes(e.freed)).font(.rounded(14, .semibold)).monospacedDigit()
                                        }
                                        Text(e.date.formatted(date: .omitted, time: .standard))
                                            .font(.caption).foregroundStyle(.tertiary)
                                    }
                                    if !e.detail.isEmpty {
                                        Text(e.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                }
                            }
                            .padding(12)
                        }
                    }
                    .padding(6)
                    .card()
                    .padding(28)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(tr("清理记录", "History"))
    }
}
