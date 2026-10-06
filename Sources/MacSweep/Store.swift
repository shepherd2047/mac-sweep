import AppKit
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published private(set) var items: [Category: [SweepItem]] = [:]
    @Published private(set) var scanning: Set<Category> = []
    @Published var selected: Set<String> = []
    @Published private(set) var disk = DiskInfo.current()
    @Published private(set) var trashSize: Int64?
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var cleaning = false
    @Published private(set) var progress: (done: Int, total: Int) = (0, 0)
    @Published private(set) var hasFullDiskAccess = FS.hasFullDiskAccess()
    @Published private(set) var lastScan: Date?

    var isScanning: Bool { !scanning.isEmpty }

    private var activeObserver: NSObjectProtocol?

    init() {
        // Coming back from System Settings after granting Full Disk Access: rescan so the
        // protected locations (Containers, Trash, Downloads, Documents) show up.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.hasFullDiskAccess, FS.hasFullDiskAccess() else { return }
                self.hasFullDiskAccess = true
                await self.scan()
            }
        }
    }

    func items(_ c: Category) -> [SweepItem] { items[c] ?? [] }
    func total(_ c: Category) -> Int64 { items(c).reduce(0) { $0 + $1.size } }
    func safeTotal(_ c: Category) -> Int64 { items(c).filter { $0.risk == .safe }.reduce(0) { $0 + $1.size } }

    var allItems: [SweepItem] { Category.allCases.flatMap { items($0) } }
    var selectedItems: [SweepItem] { allItems.filter { selected.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { self.selected.contains(id) },
                set: { if $0 { self.selected.insert(id) } else { self.selected.remove(id) } })
    }

    func selectSafe(in cats: [Category] = Category.allCases) {
        for c in cats { for i in items(c) where i.risk == .safe { selected.insert(i.id) } }
    }

    func deselect(in c: Category) {
        for i in items(c) { selected.remove(i.id) }
    }

    // MARK: scan

    func scan() async {
        guard !isScanning else { return }
        scanning = Set(Category.allCases)
        items = [:]
        selected = []
        hasFullDiskAccess = FS.hasFullDiskAccess()
        refreshDisk()

        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        let inv = await Task.detached(priority: .userInitiated) { AppInventory() }.value

        await withTaskGroup(of: (Category, [SweepItem]).self) { group in
            group.addTask {
                // Caches skips whatever the orphan scan already claimed.
                let orphans = await OrphanScanner(inv: inv).scan()
                await self.publish(.orphans, orphans)
                let claimed = Set(orphans.flatMap { $0.paths.map(\.path) })
                return (.caches, await CacheScanner(inv: inv, claimed: claimed).scan())
            }
            group.addTask { (.apps, await AppScanner(inv: inv, running: running).scan()) }
            group.addTask { (.large, await LargeScanner().scan()) }
            group.addTask { (.dev, await DevScanner().scan()) }
            for await (c, list) in group { publish(c, list) }
        }
        lastScan = Date()
    }

    private func publish(_ c: Category, _ list: [SweepItem]) {
        items[c] = list
        scanning.remove(c)
    }

    func refreshDisk() {
        disk = DiskInfo.current()
        Task.detached(priority: .utility) {
            let t = Cleaner.trashSize()
            await MainActor.run { self.trashSize = t }
        }
    }

    // MARK: clean

    func cleanSelected() async {
        let chosen = selectedItems
        guard !chosen.isEmpty, !cleaning else { return }
        cleaning = true
        progress = (0, chosen.count)
        let before = DiskInfo.current().free

        for item in chosen {
            let r = await Cleaner.perform(item)
            log.insert(LogEntry(ok: r.ok, title: item.title, detail: r.detail, freed: r.ok ? item.size : 0), at: 0)
            if r.ok {
                items[item.category]?.removeAll { $0.id == item.id }
                selected.remove(item.id)
            }
            progress.done += 1
        }

        refreshDisk()
        let gained = disk.free - before
        log.insert(LogEntry(ok: true, title: "本次清理完成",
                            detail: "处理 \(chosen.count) 项。移到废纸篓的空间要清倒废纸篓后才会释放；目前可用空间变化 \(formatBytes(gained))",
                            freed: 0), at: 0)
        cleaning = false
    }

    func emptyTrash() {
        if Cleaner.emptyTrash() {
            log.insert(LogEntry(ok: true, title: "已清倒废纸篓", detail: "", freed: trashSize ?? 0), at: 0)
        }
        refreshDisk()
    }

    func reveal(_ item: SweepItem) {
        NSWorkspace.shared.activateFileViewerSelecting(item.paths.filter(FS.exists))
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}
