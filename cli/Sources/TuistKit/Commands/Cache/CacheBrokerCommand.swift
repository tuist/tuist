import ArgumentParser
import Path
import TuistSupport

public struct CacheBrokerCommand: AsyncParsableCommand, HARRecordingCommand {
    public var shouldRecordHAR: Bool { false }

    public init() {}
    public static let configuration = CommandConfiguration(
        commandName: "cache-broker",
        abstract: "Run the machine-wide Xcode compilation-cache broker",
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
        try await CacheBrokerCommandService().run(url: url, accountHandle: account)
    }
}
