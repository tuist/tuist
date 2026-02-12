import ArgumentParser
import Foundation
import TuistEnvKey
import TuistServer

public struct ProjectCreateCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "create",
            _superCommandName: "project",
            abstract: "Create a new project."
        )
    }

    @Argument(
        help: "The project to create. The full handle must be in the format of account-handle/project-handle.",
        completion: .directory,
        envKey: .projectCreateFullHandle
    )
    var fullHandle: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .projectCreatePath
    )
    var path: String?

    @Option(
        name: .long,
        help: "The build system used by the project (xcode or gradle). Defaults to xcode.",
        envKey: .projectCreateBuildSystem
    )
    var buildSystem: ServerProject.BuildSystem?

    public func run() async throws {
        try await ProjectCreateService().run(
            fullHandle: fullHandle,
            directory: path,
            buildSystem: buildSystem
        )
    }
}

extension ServerProject.BuildSystem: @retroactive ExpressibleByArgument {}
