import Basic
import Foundation
import TuistCore
import Utility

class GenerateCommand: NSObject, Command {

    // MARK: - Static

    static let command = "generate"
    static let overview = "Generates an Xcode workspace to start working on the project."

    // MARK: - Attributes

    fileprivate let graphLoader: GraphLoading
    fileprivate let workspaceGenerator: WorkspaceGenerating
    fileprivate let printer: Printing
    fileprivate let system: Systeming
    fileprivate let resourceLocator: ResourceLocating
    fileprivate let carthageController: CarthageControlling

    let pathArgument: OptionArgument<String>
    let configArgument: OptionArgument<String>
    let skipCarthage: OptionArgument<Bool>

    // MARK: - Init

    required convenience init(parser: ArgumentParser) {
        self.init(graphLoader: GraphLoader(),
                  workspaceGenerator: WorkspaceGenerator(),
                  parser: parser)
    }

    init(graphLoader: GraphLoading,
         workspaceGenerator: WorkspaceGenerating,
         parser: ArgumentParser,
         carthageController: CarthageControlling = CarthageController(),
         printer: Printing = Printer(),
         system: Systeming = System(),
         resourceLocator: ResourceLocating = ResourceLocator()) {
        let subParser = parser.add(subparser: GenerateCommand.command, overview: GenerateCommand.overview)
        self.graphLoader = graphLoader
        self.workspaceGenerator = workspaceGenerator
        self.carthageController = carthageController
        self.printer = printer
        self.system = system
        self.resourceLocator = resourceLocator
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path where the Project.swift file will be generated.",
                                     completion: .filename)
        configArgument = subParser.add(option: "--config",
                                       shortName: "-c",
                                       kind: String.self,
                                       usage: "The configuration that will be generated.",
                                       completion: .filename)
        skipCarthage = subParser.add(option: "--skip-carthage",
                                     shortName: nil,
                                     kind: Bool.self,
                                     usage: "Skips updating Carthage dependencies.",
                                     completion: .filename)
    }

    func run(with arguments: ArgumentParser.Result) throws {
        printer.print(section: "Generating project")

        let path = self.path(arguments: arguments)
        let config = try parseConfig(arguments: arguments)
        let graph = try graphLoader.load(path: path)

        if !skipCarthage(arguments: arguments) {
            try carthageController.updateIfNecessary(graph: graph)
        }

        let options = GenerationOptions(buildConfiguration: config)

        try workspaceGenerator.generate(path: path,
                                        graph: graph,
                                        options: options,
                                        system: system,
                                        printer: printer,
                                        resourceLocator: resourceLocator)

        printer.print(success: "Project generated")
    }

    // MARK: - Fileprivate

    fileprivate func skipCarthage(arguments: ArgumentParser.Result) -> Bool {
        if let skipCarthage = arguments.get(skipCarthage) {
            return skipCarthage
        }
        return false
    }

    fileprivate func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: AbsolutePath.current)
        } else {
            return AbsolutePath.current
        }
    }

    private func parseConfig(arguments: ArgumentParser.Result) throws -> BuildConfiguration {
        var config: BuildConfiguration = .debug
        if let configString = arguments.get(configArgument) {
            guard let buildConfiguration = BuildConfiguration(rawValue: configString.lowercased()) else {
                let error = ArgumentParserError.invalidValue(argument: "config",
                                                             error: ArgumentConversionError.custom("config can only be debug or release"))
                throw error
            }
            config = buildConfiguration
        }
        return config
    }
}
