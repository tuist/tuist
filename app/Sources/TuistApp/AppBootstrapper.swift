import SwiftUI
import TuistLogging
import TuistServer

@MainActor
final class AppBootstrapper: ObservableObject {
    @Published private(set) var isReady = false

    private let applicationLogUploader = ApplicationLogUploader(serverURL: ServerEnvironmentService().url())

    init() {
        Task {
            await ApplicationLogStore.current.bootstrap()
            isReady = true
        }
        _ = withAppDependencies {
            Task { [applicationLogUploader] in
                await applicationLogUploader.run()
            }
        }
    }

    func uploadLogs() {
        _ = withAppDependencies {
            Task { [applicationLogUploader] in
                await applicationLogUploader.upload()
            }
        }
    }

    /// Tasks inherit task-local values only from the scope that creates them, so the uploader's tasks read the same
    /// credentials the rest of the app does.
    private func withAppDependencies<T>(_ operation: () -> T) -> T {
        #if os(macOS)
            ServerCredentialsStore.$current.withValue(ServerCredentialsStore(backend: .keychain)) {
                CachedValueStore.$current.withValue(CachedValueStore(backend: .inSystemProcess)) {
                    operation()
                }
            }
        #else
            operation()
        #endif
    }
}
