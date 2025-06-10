import FileSystem
import Foundation
import Mockable
import TuistSupport

@Mockable
protocol BackgroundProcessRunning {
    func runInBackground(
        _ arguments: [String],
        environment: [String: String]
    ) async throws
}

struct BackgroundProcessRunner: BackgroundProcessRunning {
    private let fileSystem: FileSysteming

    init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    func runInBackground(
        _ arguments: [String],
        environment: [String: String]
    ) async throws {
        let process = Process()
        process.environment = environment
        process.launchPath = arguments.first
        process.arguments = Array(arguments.dropFirst())
        process.unbind(.isIndeterminate)
        try process.run()
        let pidPath = Environment.current.stateDirectory.appending(component: "tuist.pid")
        if try await fileSystem.exists(pidPath) {
            try await fileSystem.remove(pidPath)
        }
        try await fileSystem.writeText("\(process.processIdentifier)", at: pidPath)
    }
}
