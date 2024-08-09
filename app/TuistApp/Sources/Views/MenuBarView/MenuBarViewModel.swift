import Foundation
import Sparkle

final class MenuBarViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
    
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
