import AppKit
import SwiftUI

@main
struct MacSweepApp: App {
    @StateObject private var store = Store()

    init() {
        if CommandLine.arguments.contains("--dump") { Dump.run() }
        // Lets `swift run` show a normal window with a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("MacSweep") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 560)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1200, height: 780)
        // Without this the window can be resized below the content's minimum and SwiftUI clips it.
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("重新扫描") { Task { await store.scan() } }
                    .keyboardShortcut("r")
                    .disabled(store.isScanning)
            }
        }
    }
}
