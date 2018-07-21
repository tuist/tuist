import Basic
import Foundation
import Utility
import xpmcore

class GenerateCommand: NSObject, Command {

    // MARK: - Attributes

    static let command = "generate"
    static let overview = "Generates an Xcode workspace to start working on the project."
    fileprivate let graphLoaderContext: GraphLoaderContexting
    fileprivate let graphLoader: GraphLoading
    fileprivate let workspaceGenerator: WorkspaceGenerating
    fileprivate let context: CommandsContexting
    let pathArgument: OptionArgument<String>
    let configArgument: OptionArgument<String>

    // MARK: - Init

    required convenience init(parser: ArgumentParser) {
        self.init(graphLoaderContext: GraphLoaderContext(),
                  graphLoader: GraphLoader(),
                  workspaceGenerator: WorkspaceGenerator(),
                  parser: parser,
                  context: CommandsContext())
    }

    init(graphLoaderContext: GraphLoaderContexting,
         graphLoader: GraphLoading,
         workspaceGenerator: WorkspaceGenerating,
         parser: ArgumentParser,
         context: CommandsContexting) {
        let subParser = parser.add(subparser: GenerateCommand.command, overview: GenerateCommand.overview)
        self.graphLoaderContext = graphLoaderContext
        self.graphLoader = graphLoader
        self.workspaceGenerator = workspaceGenerator
        self.context = context
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
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)
        let config = try parseConfig(arguments: arguments)
        let context = try GeneratorContext(graph: graphLoader.load(path: path))
        try workspaceGenerator.generate(path: path, context: context, options: GenerationOptions(buildConfiguration: config))
        self.context.printer.print(success: "Project generated.")
    }

    // MARK: - Fileprivate

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
