import ArgumentParser
import Foundation

public struct TokenCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "token",
            _superCommandName: "auth",
            abstract: "Prints the authentication token for a server URL",
            shouldDisplay: false
        )
    }

    @Option(
        name: .long,
        help: "The URL of the server. Defaults to the current server."
    )
    var url: String?

    @Option(
        name: .long,
        help: "The `account/project` the token will be used against. Exchanges the credential for one a cache node can verify by itself."
    )
    var project: String?

    public func run() async throws {
        try await AuthTokenService().run(serverURL: url, projectHandle: project)
    }
}
