import Basic
import Foundation
import Utility
import xpmcore

public class GenerateCommand: NSObject, Command {
    /// Command name (static).
    public static let command = "generate"

    /// Command description.
    public static let overview = "Generates an Xcode workspace to start working on the project."

    /// Graph loader context.
    fileprivate let graphLoaderContext: GraphLoaderContexting

    /// Graph loader.
    fileprivate let graphLoader: GraphLoading

    /// Workspace generator.
    fileprivate let workspaceGenerator: WorkspaceGenerating

    /// Context.
    fileprivate let context: CommandsContexting

    /// Path argument.
    let pathArgument: OptionArgument<String>

    /// Config argument.
    let configArgument: OptionArgument<String>

    /// Initializes the generate command with the argument parser.
    ///
    /// - Parameter parser: argument parser.
    public required convenience init(parser: ArgumentParser) {
        self.init(graphLoaderContext: GraphLoaderContext(),
                  graphLoader: GraphLoader(),
                  workspaceGenerator: WorkspaceGenerator(),
                  parser: parser,
                  context: CommandsContext())
    }

    /// Initializes the command with the printer and the graph loading context.
    ///
    /// - Parameters:
    ///   - graphLoaderContext: graph loading context.
    ///   - graphLoader: graph loader.
    ///   - workspaceGenerator: workspace generator,
    ///   - parser: argument parser.
    ///   - context: context.
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

    /// Runs the command.
    ///
    /// - Parameter _: argument parser arguments.
    /// - Throws: an error if the command cannot be executed.
    public func run(with arguments: ArgumentParser.Result) throws {
        let path = parsePath(arguments: arguments)
        let config = try parseConfig(arguments: arguments)
        let context = try GeneratorContext(graph: graphLoader.load(path: path))
        try workspaceGenerator.generate(path: path, context: context, options: GenerationOptions(buildConfiguration: config))
        self.context.printer.print(section: "Generate command succeeded 🎉")
    }

    /// Parses the arguments and returns the path to the folder where the manifest file is.
    ///
    /// - Parameter arguments: argument parser result.
    /// - Returns: the path to th efolder where the manifest is.
    private func parsePath(arguments: ArgumentParser.Result) -> AbsolutePath {
        var path: AbsolutePath! = arguments.get(pathArgument).map({ AbsolutePath($0) })
        if path == nil {
            path = AbsolutePath.current
        }
        return path
    }

    /// Parses the arguments and returns the build configuration that we should use for generating the projects.
    ///
    /// - Parameters:
    ///     - arguments: argument parser result.
    /// - Returns: The build configuration.
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
