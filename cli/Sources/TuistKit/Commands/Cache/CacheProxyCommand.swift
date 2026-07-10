import ArgumentParser
import Path
import TuistSupport

public struct CacheProxyCommand: AsyncParsableCommand, HARRecordingCommand {
    public var shouldRecordHAR: Bool { false }

    public init() {}
    public static let configuration = CommandConfiguration(
        commandName: "cache-proxy",
        abstract: "Run the machine-wide Xcode compilation-cache proxy",
        shouldDisplay: false
    )

    @Option(
        name: .shortAndLong,
        help: "The server URL. Defaults to production URL if not specified."
    )
    var url: String?

    @Option(
        help: "The account handle used to resolve the cache endpoint."
    )
    var account: String?

    public func run() async throws {
        try await CacheProxyCommandService().run(url: url, accountHandle: account)
    }
}
