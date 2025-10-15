import ArgumentParser
import Path
import TuistSupport

struct CacheStartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache-start",
        abstract: "Start a proxy server to listen for Xcode Compilation Cache requests",
        shouldDisplay: false
    )

    @Argument(
        help: "The full handle of the project (account-handle/project-handle)."
    )
    var fullHandle: String

    @Option(
        name: .shortAndLong,
        help: "The server URL. Defaults to production URL if not specified."
    )
    var url: String?

    func run() async throws {
        try await CacheStartCommandService().run(
            fullHandle: fullHandle,
            url: url
        )
    }
}
