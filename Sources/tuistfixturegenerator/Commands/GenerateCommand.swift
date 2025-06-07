import ArgumentParser
import Foundation
import TSCBasic
import TSCUtility
import TuistSupport

enum GenerateCommandError: Error {
    case invalidPath
}

struct GenerateCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "generate",
            abstract: "Generates large fixtures for the purposes of stress testing Tuist.",
            subcommands: []
        )
    }

    @Option(
        name: .long,
        help: "The path where the fixture will be generated.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: .long,
        help: "The number of projects to generate."
    )
    var projects: Int?

    @Option(
        name: .long,
        help: "The number of targets to generate within each project."
    )
    var targets: Int?

    @Option(
        name: .long,
        help: "The number of sources to generate within each target."
    )
    var sources: Int?

    func run() async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path ?? "Fixture")

        let config = GeneratorConfig(
            projects: projects ?? GeneratorConfig.default.projects,
            targets: targets ?? GeneratorConfig.default.targets,
            sources: sources ?? GeneratorConfig.default.sources
        )
        let generator = Generator(fileSystem: localFileSystem, config: config)

        try generator.generate(at: TSCBasic.AbsolutePath(validating: path.pathString))
    }
}
