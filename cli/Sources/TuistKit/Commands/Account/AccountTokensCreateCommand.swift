import ArgumentParser
import Foundation
import TuistServer
import TuistSupport

extension Components.Schemas.CreateAccountToken.scopesPayloadPayload: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

struct AccountTokensCreateCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "create",
            _superCommandName: "tokens",
            abstract: "Create a new Tuist account token."
        )
    }

    @Argument(
        help: "The account handle to create the token for.",
        envKey: .accountTokensAccountHandle
    )
    var accountHandle: String

    @Option(
        name: .shortAndLong,
        parsing: .upToNextOption,
        help: "The scopes for the token.",
        envKey: .accountTokensScopes
    )
    var scopes: [Components.Schemas.CreateAccountToken.scopesPayloadPayload]

    @Option(
        name: .shortAndLong,
        help: "A friendly name for the token.",
        envKey: .accountTokensName
    )
    var name: String

    @Option(
        name: .shortAndLong,
        help: "When the token should expire. Use format like '30d' (days), '6m' (months), or '1y' (years). If not specified, the token never expires.",
        envKey: .accountTokensExpires
    )
    var expires: String?

    @Flag(
        name: .long,
        help: "Grant the token access to all projects in the account."
    )
    var allProjects: Bool = false

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The project handles to grant the token access to. Only used when --all-projects is not set.",
        envKey: .accountTokensProjects
    )
    var projects: [String] = []

    @Option(
        name: .long,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .accountTokensPath
    )
    var path: String?

    func run() async throws {
        try await AccountTokensCreateCommandService().run(
            accountHandle: accountHandle,
            scopes: scopes,
            name: name,
            expires: expires,
            allProjects: allProjects,
            projects: projects,
            directory: path
        )
    }
}
