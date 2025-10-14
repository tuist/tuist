import ArgumentParser
import TuistSupport
import Path

struct CacheStartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache-start",
        abstract: "Start a proxy server to listen for Xcode Compilation Cache requests",
        shouldDisplay: false
    )
    
    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cacheStartPath
    )
    var path: String?

    func run() async throws {
        try await CacheStartCommandService().run(
            path: self.path(path)
        )
    }
    
    private func path(_ path: String?) async throws -> AbsolutePath {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        if let path {
            return try AbsolutePath(
                validating: path, relativeTo: currentWorkingDirectory
            )
        } else {
            return currentWorkingDirectory
        }
    }
}
