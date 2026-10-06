import SwiftUI

enum SortKey: String, CaseIterable, Identifiable {
    case size, age, name
    var id: String { rawValue }

    var title: String {
        switch self {
        case .size: tr("按大小", "By size")
        case .age: tr("按最后使用", "By last use")
        case .name: tr("按名称", "By name")
        }
    }
}

struct CategoryView: View {
    let category: Category
    @EnvironmentObject var store: Store
    @State private var riskFilter: Risk? = nil
    @State private var search = ""
    @State private var sort: SortKey = .size

    private var all: [SweepItem] { store.items(category) }

    private var rows: [SweepItem] {
        let filtered = all
            .filter { riskFilter == nil || $0.risk == riskFilter }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search) }
        switch sort {
        case .size: return filtered.sorted { $0.size > $1.size }
        case .age: return filtered.sorted { $0.lastUsedSort < $1.lastUsedSort }
        case .name: return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if category == .orphans && !store.hasFullDiskAccess { FDABanner() }
                controls
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 90) // room for the floating clean bar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(category.title)
        .searchable(text: $search, placement: .toolbar, prompt: tr("搜索名称或路径", "Search name or path"))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            IconTile(category, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title).font(.rounded(26))
                // No fixedSize: NavigationSplitView measures minimum height at a tiny width,
                // where a non-compressible paragraph grows ~1000pt and breaks the window layout.
                Text(category.blurb).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(store.total(category)))
                    .font(.rounded(30))
                    .foregroundStyle(category.gradient)
                    .monospacedDigit()
                Text(tr("\(all.count) 项", "\(all.count) items")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            FilterChip(title: tr("全部", "All"), count: all.count, color: .accentColor, on: riskFilter == nil) { riskFilter = nil }
            ForEach(Risk.allCases, id: \.self) { r in
                FilterChip(title: r.title, count: all.filter { $0.risk == r }.count, color: r.color, on: riskFilter == r) {
                    riskFilter = riskFilter == r ? nil : r
                }
            }
            Spacer()
            Menu {
                Picker(tr("排序", "Sort"), selection: $sort) {
                    ForEach(SortKey.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(sort.title, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.trailing, 6)
            Button(tr("全选安全项", "Select Safe")) { store.selectSafe(in: [category]) }
                .disabled(all.allSatisfy { $0.risk != .safe })
            Button(tr("全不选", "Select None")) { store.deselect(in: category) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.scanning.contains(category) {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(tr("正在扫描…", "Scanning…")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 80)
        } else if rows.isEmpty {
            ContentUnavailableView(search.isEmpty ? tr("这里很干净", "All clean here") : tr("没有匹配项", "No matches"),
                                   systemImage: search.isEmpty ? "sparkles" : "magnifyingglass",
                                   description: Text(search.isEmpty ? tr("没有找到可清理的项目", "Nothing to clean was found") : tr("换个关键词试试", "Try another search")))
                .padding(.vertical, 60)
        } else {
            let maxSize = max(rows.map(\.size).max() ?? 1, 1)
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().padding(.leading, 96) }
                    ItemRow(item: item, maxSize: maxSize, isOn: store.binding(item.id))
                }
            }
            .padding(6)
            .card()
        }
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let color: Color
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background((on ? Color.white : color).opacity(on ? 0.25 : 0.15), in: Capsule())
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 11).padding(.vertical, 5)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? AnyShapeStyle(color) : AnyShapeStyle(Color.primary.opacity(0.06)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(count == 0 && !on ? 0.45 : 1)
    }
}

struct ItemRow: View {
    let item: SweepItem
    let maxSize: Int64
    @Binding var isOn: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            Toggle("", isOn: $isOn).toggleStyle(.checkbox).labelsHidden()
            ItemIcon(item: item)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                    RiskBadge(risk: item.risk)
                }
                Text(item.reason)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 6) {
                Text(formatBytes(item.size))
                    .font(.rounded(15, .semibold)).monospacedDigit()
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 96, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(item.category.gradient)
                            .frame(width: max(5, 96 * CGFloat(Double(item.size) / Double(maxSize))), height: 5)
                    }
                Text(formatAge(item.lastUsed)).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOn ? item.category.tint.opacity(0.12) : hover ? Color.primary.opacity(0.04) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .onHover { hover = $0 }
        .help(item.paths.map(\.path).joined(separator: "\n"))
        .contextMenu { ItemMenu(item: item) }
    }
}

struct ItemMenu: View {
    let item: SweepItem
    @EnvironmentObject var store: Store

    var body: some View {
        Button(tr("在访达中显示", "Show in Finder")) { store.reveal(item) }
        Button(tr("拷贝路径", "Copy Path")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.paths.map(\.path).joined(separator: "\n"), forType: .string)
        }
    }
}

struct FDABanner: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(symbol: "lock.shield.fill",
                     gradient: LinearGradient(colors: [.orange, .red.opacity(0.85)], startPoint: .top, endPoint: .bottom),
                     size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("需要完全磁盘访问权限", "Full Disk Access needed")).font(.headline)
                Text(tr("其他软件的 Containers、废纸篓、下载、文稿受 macOS 隐私保护，目前跳过不扫。授权一次永久有效，回到这里会自动重新扫描。", "Other apps' Containers, the Trash, Downloads and Documents are protected by macOS privacy and are skipped for now. Grant access once and MacSweep rescans when you come back."))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button(tr("打开设置", "Open Settings")) { store.openFullDiskAccessSettings() }
                    .buttonStyle(.borderedProminent)
                Button(tr("在访达中显示 MacSweep", "Show MacSweep in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .buttonStyle(.link).font(.caption)
            }
        }
        .padding(14)
        .card()
    }
}
