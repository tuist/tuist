import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudProjectTokenCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "token",
            _superCommandName: "project",
            abstract: "Get a project token. You can save this token in the `TUIST_CONFIG_CLOUD_TOKEN` environment variable to use the remote cache on the CI."
        )
    }

    @Argument(
        help: "The name of the project to get the token for.",
        completion: .directory,
        envKey: .cloudProjectTokenProjectName
    )
    var projectName: String

    @Option(
        name: .shortAndLong,
        help: "Organization of the project. If not specified, it defaults to your user account.",
        envKey: .cloudProjectTokenOrganizationName
    )
    var organizationName: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudProjectTokenPath
    )
    var path: String?

    func run() async throws {
        try await CloudProjectTokenService().run(
            projectName: projectName,
            organizationName: organizationName,
            directory: path
        )
    }
}
