import ArgumentParser
import Path
import TuistSupport

/// Machines set up for the Xcode cache before the machine-wide CAS proxy have a
/// per-project LaunchAgent that runs this command. It no longer serves the cache:
/// it removes that LaunchAgent so it is not started again.
public struct CacheStartCommand: AsyncParsableCommand, HARRecordingCommand {
    public var shouldRecordHAR: Bool { false }

    public init() {}
    public static let configuration = CommandConfiguration(
        commandName: "cache-start",
        abstract: "Remove the LaunchAgent of the retired per-project Xcode cache daemon",
        shouldDisplay: false
    )

    @Argument(
        help: "The full handle of the project (account-handle/project-handle)."
    )
    var fullHandle: String

    @Option(
        name: .shortAndLong,
        help: "Unused. Accepted so that existing LaunchAgents keep parsing."
    )
    var url: String?

    @Flag(
        inversion: .prefixedNo,
        help: "Unused. Accepted so that existing LaunchAgents keep parsing."
    )
    var upload: Bool = true

    public func run() async throws {
        try await CacheStartCommandService().run(fullHandle: fullHandle)
    }
}
