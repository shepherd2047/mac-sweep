import SwiftUI

struct CategoryView: View {
    let category: Category
    @EnvironmentObject var store: Store
    @State private var riskFilter: Risk? = nil
    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\SweepItem.size, order: .reverse)]

    private var rows: [SweepItem] {
        store.items(category)
            .filter { riskFilter == nil || $0.risk == riskFilter }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            Divider()
            if store.scanning.contains(category) {
                ProgressView("正在扫描…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView(search.isEmpty ? "这里很干净" : "没有匹配项",
                                       systemImage: search.isEmpty ? "sparkles" : "magnifyingglass",
                                       description: Text(search.isEmpty ? "没有找到可清理的项目" : "换个关键词试试"))
            } else {
                table
            }
        }
        .navigationTitle(category.title)
        .searchable(text: $search, placement: .toolbar, prompt: "搜索名称或路径")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(category.title, systemImage: category.icon).font(.title2.bold())
                Spacer()
                Text(formatBytes(store.total(category))).font(.title2.monospacedDigit()).foregroundStyle(.secondary)
            }
            // No fixedSize here: NavigationSplitView measures its minimum height at a tiny width,
            // where a non-compressible paragraph turns into ~1000pt and pushes the window
            // content up under the toolbar.
            Text(category.blurb).foregroundStyle(.secondary).lineLimit(3)
            if category == .orphans && !store.hasFullDiskAccess {
                FDABanner()
            }
            HStack {
                Picker("风险", selection: $riskFilter) {
                    Text("全部").tag(Risk?.none)
                    ForEach(Risk.allCases, id: \.self) { r in
                        Text("\(r.title) (\(store.items(category).filter { $0.risk == r }.count))").tag(Risk?.some(r))
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                Spacer()
                Button("全选安全项") { store.selectSafe(in: [category]) }
                Button("全不选") { store.deselect(in: category) }
            }
        }
    }

    private var table: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("") { item in
                Toggle("", isOn: store.binding(item.id))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .width(20)

            TableColumn("项目", value: \.title) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).lineLimit(1)
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .help(item.paths.map(\.path).joined(separator: "\n"))
                .contextMenu { ItemMenu(item: item) }
            }
            .width(min: 180, ideal: 280)

            TableColumn("大小", value: \.size) { item in
                Text(formatBytes(item.size)).monospacedDigit()
            }
            .width(min: 70, ideal: 80)

            TableColumn("最后使用/修改", value: \.lastUsedSort) { item in
                Text(formatAge(item.lastUsed)).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("风险", value: \.risk) { item in
                RiskBadge(risk: item.risk)
            }
            .width(60)

            TableColumn("说明") { item in
                Text(item.reason).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    .help(item.reason)
            }
            .width(min: 160, ideal: 320)
        }
    }
}

struct ItemMenu: View {
    let item: SweepItem
    @EnvironmentObject var store: Store

    var body: some View {
        Button("在访达中显示") { store.reveal(item) }
        Button("拷贝路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.paths.map(\.path).joined(separator: "\n"), forType: .string)
        }
    }
}

struct RiskBadge: View {
    let risk: Risk

    var body: some View {
        Text(risk.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(risk.color)
            .background(risk.color.opacity(0.15), in: Capsule())
    }
}

struct FDABanner: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("没有完全磁盘访问权限").font(.callout.bold())
                Text("其他软件的 Containers、废纸篓、下载、文稿受 macOS 隐私保护，目前跳过不扫。在设置里把 MacSweep 打开即可，授权一次永久有效，回到这里会自动重新扫描。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button("打开设置") { store.openFullDiskAccessSettings() }
                Button("在访达中显示 MacSweep") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .buttonStyle(.link).font(.caption)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
