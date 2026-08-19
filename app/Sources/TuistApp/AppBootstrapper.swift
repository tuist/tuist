import SwiftUI
import TuistLogging

@MainActor
final class AppBootstrapper: ObservableObject {
    @Published private(set) var isReady = false

    init() {
        Task {
            await ApplicationLogStore.current.bootstrap()
            isReady = true
        }
    }
}
