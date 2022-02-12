import Foundation
import TSCBasic
import TSCUtility

enum GenerateCommandError: Error {
    case invalidPath
}

final class GenerateCommand {
    private let pathArgument: OptionArgument<String>
    private let projectsArgument: OptionArgument<Int>
    private let targetsArgument: OptionArgument<Int>
    private let sourcesArgument: OptionArgument<Int>

    private let fileSystem: FileSystem

    init(
        fileSystem: FileSystem,
        parser: ArgumentParser
    ) {
        self.fileSystem = fileSystem

        pathArgument = parser.add(
            option: "--path",
            kind: String.self,
            usage: "The path where the fixture will be generated.",
            completion: .filename
        )
        projectsArgument = parser.add(
            option: "--projects",
            shortName: "-p",
            kind: Int.self,
            usage: "Number of projects to generate."
        )
        targetsArgument = parser.add(
            option: "--targets",
            shortName: "-t",
            kind: Int.self,
            usage: "Number of targets to generate within each project."
        )
        sourcesArgument = parser.add(
            option: "--sources",
            shortName: "-s",
            kind: Int.self,
            usage: "Number of sources to generate within each target."
        )
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let defaultConfig = GeneratorConfig.default

        let path = try determineFixturePath(using: arguments)
        let projects = arguments.get(projectsArgument) ?? defaultConfig.projects
        let targets = arguments.get(targetsArgument) ?? defaultConfig.targets
        let sources = arguments.get(sourcesArgument) ?? defaultConfig.sources

        let config = GeneratorConfig(projects: projects, targets: targets, sources: sources)
        let generator = Generator(fileSystem: fileSystem, config: config)

        try generator.generate(at: path)
    }

    private func determineFixturePath(using arguments: ArgumentParser.Result) throws -> AbsolutePath {
        guard let currentPath = fileSystem.currentWorkingDirectory else {
            throw GenerateCommandError.invalidPath
        }

        guard let path = arguments.get(pathArgument) else {
            return currentPath.appending(component: "Fixture")
        }
        return AbsolutePath(path, relativeTo: currentPath)
    }
}
