import SwiftUI

enum SpaceTab: String, CaseIterable, Identifiable {
    case apps
    case personal
    case system
    case folders
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: tr("按软件", "By app")
        case .personal: tr("个人文件", "Personal files")
        case .system: tr("系统", "System")
        case .folders: tr("按文件夹", "Folders")
        }
    }

    var buckets: Set<Bucket> {
        switch self {
        case .apps: [.apps]
        case .personal: [.personal]
        case .system: [.system, .macos, .hidden]
        case .folders: []
        }
    }
}

struct SpaceView: View {
    @EnvironmentObject var space: SpaceModel
    @State private var tab: SpaceTab = .apps
    @State private var search = ""
    @State private var expanded: Set<String> = []
    @State private var showAll = false
    @State private var folder: [SpaceNode] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let r = space.report {
                    DiskMap(report: r, rescan: { Task { await space.scan() } }, scanning: space.scanning)
                    Picker("", selection: $tab) {
                        ForEach(SpaceTab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)
                    if tab == .folders {
                        FolderBrowser(report: r, stack: $folder)
                    } else {
                        ownerList(r)
                    }
                } else {
                    scanningPlaceholder
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(tr("空间分析", "Space"))
        .searchable(text: $search, placement: .toolbar, prompt: tr("搜索软件或文件夹", "Search apps or folders"))
        .task { if space.report == nil { await space.scan() } }
        .onChange(of: tab) { showAll = false }
    }

    private var scanningPlaceholder: some View {
        VStack(spacing: 16) {
            IconTile(symbol: "chart.pie.fill", gradient: Bucket.apps.gradient, size: 64)
            Text(tr("正在把整块硬盘过一遍…", "Going through the whole disk…")).font(.rounded(22))
            Text(tr("大概一分钟。会看每个文件夹，把软件本体和它散落在资源库里的数据合到一起算。", "About a minute. Every folder is checked, and each app bundle is combined with its data scattered across the Library."))
                .foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
            ProgressView().controlSize(.small)
            Text(tr("已扫描 \(space.scannedFiles.formatted()) 个文件", "\(space.scannedFiles.formatted()) files scanned")).monospacedDigit().font(.callout)
            Text(space.currentPath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    @ViewBuilder
    private func ownerList(_ r: SpaceReport) -> some View {
        let all = r.owners(in: tab.buckets).filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                || $0.parts.contains { ($0.path ?? "").localizedCaseInsensitiveContains(search) }
        }
        let shown = showAll ? all : Array(all.prefix(40))
        let maxSize = max(all.first?.total ?? 1, 1)

        if tab == .apps {
            Label(tr("每个软件 = 应用本体 + 它在 ~/Library 里的沙盒容器、应用支持、缓存等全部数据。点开看具体在哪。", "Each app = app bundle + all its data in ~/Library: sandbox containers, Application Support, caches and more. Expand to see where."), systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
        }
        if all.isEmpty {
            ContentUnavailableView.search(text: search).padding(.vertical, 40)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, o in
                    if i > 0 { Divider().padding(.leading, 64) }
                    OwnerRow(owner: o, maxSize: maxSize, expanded: expanded.contains(o.id)) {
                        if expanded.contains(o.id) { expanded.remove(o.id) } else { expanded.insert(o.id) }
                    }
                }
                if all.count > shown.count {
                    Divider()
                    Button(tr("显示其余 \(all.count - shown.count) 项（共 \(formatBytes(all.dropFirst(shown.count).reduce(0) { $0 + $1.total }))）", "Show \(all.count - shown.count) more (\(formatBytes(all.dropFirst(shown.count).reduce(0) { $0 + $1.total })) total)")) {
                        showAll = true
                    }
                    .buttonStyle(.link)
                    .padding(12)
                }
            }
            .padding(6)
            .card()
        }
    }
}

/// Whole-disk bar split into buckets, with a plain-language line for each.
struct DiskMap: View {
    let report: SpaceReport
    let rescan: () -> Void
    let scanning: Bool

    var body: some View {
        let total = Double(max(report.container.total, 1))
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("硬盘里都是什么", "What’s on your disk")).font(.headline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formatBytes(report.container.total - report.container.free))
                            .font(.rounded(40, .heavy)).monospacedDigit()
                        Text(tr("已用 / 共 \(formatBytes(report.container.total))", "used of \(formatBytes(report.container.total))")).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action: rescan) {
                        if scanning { ProgressView().controlSize(.small) } else { Label(tr("重新分析", "Rescan"), systemImage: "arrow.clockwise") }
                    }
                    .disabled(scanning)
                    Text(tr("\(report.date.formatted(date: .omitted, time: .shortened)) · \(report.scannedFiles.formatted()) 个文件", "\(report.date.formatted(date: .omitted, time: .shortened)) · \(report.scannedFiles.formatted()) files"))
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            SegmentBar(segments: Bucket.allCases.map {
                .init(id: $0.rawValue, value: Double(report.total($0)) / total, fill: AnyShapeStyle($0.gradient))
            }, height: 22)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .topLeading)], alignment: .leading, spacing: 14) {
                ForEach(Bucket.allCases) { b in
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(b.gradient).frame(width: 10, height: 10)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(b.title).font(.callout.weight(.semibold))
                                Text(formatBytes(report.total(b))).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Text(b.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
            }
        }
        .padding(24)
        .card(radius: 18)
    }
}

struct OwnerRow: View {
    let owner: Owner
    let maxSize: Int64
    let expanded: Bool
    let toggle: () -> Void
    @State private var hover = false

    private var summary: String {
        if !owner.note.isEmpty { return owner.note }
        return owner.parts.sorted { $0.size > $1.size }.prefix(3)
            .map { "\($0.label) \(formatBytes($0.size))" }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                icon.frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(owner.name).font(.body.weight(.medium)).lineLimit(1)
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(formatBytes(owner.total)).font(.rounded(15, .semibold)).monospacedDigit()
                    Capsule().fill(Color.primary.opacity(0.08)).frame(width: 110, height: 5)
                        .overlay(alignment: .leading) {
                            Capsule().fill(owner.bucket.gradient)
                                .frame(width: max(5, 110 * CGFloat(Double(owner.total) / Double(maxSize))), height: 5)
                        }
                }
                .frame(width: 120, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hover || expanded ? Color.primary.opacity(0.04) : .clear))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy(duration: 0.2)) { toggle() } }
            .onHover { hover = $0 }

            if expanded {
                VStack(spacing: 0) {
                    ForEach(owner.parts.sorted { $0.size > $1.size }.prefix(50)) { p in
                        PartRow(part: p, of: owner.total, gradient: owner.bucket.gradient)
                    }
                }
                .padding(.leading, 68).padding(.trailing, 40).padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder private var icon: some View {
        if let url = owner.iconURL {
            Image(nsImage: IconCache.icon(url)).resizable().interpolation(.high).frame(width: 38, height: 38)
        } else {
            IconTile(symbol: owner.symbol, gradient: owner.bucket.gradient, size: 34)
        }
    }
}

struct PartRow: View {
    let part: UsagePart
    let of: Int64
    let gradient: LinearGradient

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(part.label).font(.callout).lineLimit(1)
                if let p = part.path {
                    Text(FS.tilde(URL(fileURLWithPath: p))).font(.caption).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            Text("\(Int((Double(part.size) / Double(max(of, 1)) * 100).rounded()))%")
                .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            Text(formatBytes(part.size)).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
            if let p = part.path {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
                } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help(tr("在访达中显示", "Show in Finder"))
            } else {
                Color.clear.frame(width: 16)
            }
        }
        .padding(.vertical, 5)
    }
}

/// Drill-down through folders, like a file manager sorted by size.
struct FolderBrowser: View {
    let report: SpaceReport
    @Binding var stack: [SpaceNode]

    private var current: SpaceNode { stack.last ?? report.root }

    var body: some View {
        let node = current
        let maxSize = max(node.children.first?.size ?? 1, node.smallSize, 1)
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    crumb("Macintosh HD", depth: 0)
                    ForEach(Array(stack.enumerated()), id: \.element.id) { i, n in
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        crumb(n.name, depth: i + 1)
                    }
                }
            }
            HStack {
                Text(formatBytes(node.size)).font(.rounded(24)).monospacedDigit()
                if let owner = report.owner(of: node) {
                    Text(tr("属于「\(owner)」", "Belongs to “\(owner)”")).foregroundStyle(.secondary)
                }
                Spacer()
                if node !== report.root {
                    Button(tr("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }
                }
            }
            LazyVStack(spacing: 0) {
                ForEach(node.children.prefix(200)) { c in
                    FolderRow(node: c, maxSize: maxSize, owner: report.owner(of: c)) {
                        if c.isDir && !c.children.isEmpty { stack.append(c) }
                    }
                    Divider().padding(.leading, 50)
                }
                if node.smallSize > 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.secondary).frame(width: 26)
                        Text(tr("\(node.smallCount) 个小文件和小文件夹", "\(node.smallCount) small files and folders")).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatBytes(node.smallSize)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                if node.unreadable {
                    Label(tr("macOS 不让读这个文件夹", "macOS won’t allow reading this folder"), systemImage: "lock.fill").foregroundStyle(.secondary).padding(12)
                }
            }
            .padding(6)
            .card()
        }
    }

    private func crumb(_ title: String, depth: Int) -> some View {
        Button(title) { stack = Array(stack.prefix(depth)) }
            .buttonStyle(.plain)
            .font(.callout.weight(depth == stack.count ? .semibold : .regular))
            .foregroundStyle(depth == stack.count ? Color.primary : Color.accentColor)
    }
}

struct FolderRow: View {
    let node: SpaceNode
    let maxSize: Int64
    let owner: String?
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCache.icon(URL(fileURLWithPath: node.path)))
                .resizable().interpolation(.high).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).lineLimit(1).truncationMode(.middle)
                if let owner { Text(owner).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                else if node.unreadable { Text(tr("无法读取", "Unreadable")).font(.caption).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 12)
            Capsule().fill(Color.primary.opacity(0.08)).frame(width: 140, height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(Bucket.personal.gradient)
                        .frame(width: max(node.size > 0 ? 4 : 0, 140 * CGFloat(Double(node.size) / Double(maxSize))), height: 6)
                }
            Text(formatBytes(node.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                .foregroundStyle(node.isDir && !node.children.isEmpty ? Color.secondary : Color.clear)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.primary.opacity(0.04) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hover = $0 }
        .contextMenu {
            Button(tr("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }
            Button(tr("拷贝路径", "Copy path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            }
        }
    }
}
