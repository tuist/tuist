import ArgumentParser
import Foundation

public struct LoginCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "login",
            _superCommandName: "auth",
            abstract: "Log in a user"
        )
    }

    @Option(
        help: "Email to authenticate with."
    )
    var email: String?

    @Option(
        help: "Password to authenticate with."
    )
    var password: String?

    @Option(
        name: .long,
        help: "The URL of the server. Required on Linux unless TUIST_URL environment variable is set."
    )
    var serverURL: String?

    public func run() async throws {
        try await LoginService().run(
            email: email,
            password: password,
            serverURL: serverURL
        )
    }
}
