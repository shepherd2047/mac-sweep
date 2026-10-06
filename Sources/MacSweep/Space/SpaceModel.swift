import Foundation

@MainActor
final class SpaceModel: ObservableObject {
    @Published private(set) var report: SpaceReport?
    @Published private(set) var scanning = false
    @Published private(set) var scannedFiles = 0
    @Published private(set) var currentPath = ""

    func scan() async {
        guard !scanning else { return }
        scanning = true
        scannedFiles = 0
        let progress = SpaceScanner.Progress()
        let poll = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                let v = progress.value
                scannedFiles = v.files
                currentPath = v.path
            }
        }
        let r = await Task.detached(priority: .userInitiated) { SpaceAnalysis.run(progress: progress) }.value
        poll.cancel()
        report = r
        scanning = false
    }
}
