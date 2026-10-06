import AppKit
import SwiftUI

@main
struct MacSweepApp: App {
    @StateObject private var store = Store()
    @StateObject private var space = SpaceModel()

    init() {
        let args = CommandLine.arguments
        if args.contains("--dump") { Dump.run() }
        if let i = args.firstIndex(of: "--check-access"), i + 1 < args.count { AccessCheck.run(out: args[i + 1]) }
        if let i = args.firstIndex(of: "--space"), i + 1 < args.count { SpaceDump.run(out: args[i + 1]) }
        // Lets `swift run` show a normal window with a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("MacSweep") {
            ContentView()
                .environmentObject(store)
                .environmentObject(space)
                .frame(minWidth: 860, minHeight: 560)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1200, height: 780)
        // Without this the window can be resized below the content's minimum and SwiftUI clips it.
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button(tr("重新扫描", "Rescan")) { Task { await store.scan() } }
                    .keyboardShortcut("r")
                    .disabled(store.isScanning)
            }
        }
    }
}
