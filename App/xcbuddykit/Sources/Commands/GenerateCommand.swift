import Basic
import Foundation
import Utility

enum GenerateCommandError: Error, CustomStringConvertible, Equatable {
    static func == (_: GenerateCommandError, _: GenerateCommandError) -> Bool {
        return true
    }

    var description: String {
        return ""
    }
}

public class GenerateCommand: NSObject, Command {
    public let command = "generate"
    public let overview = "Generates an Xcode workspace to start working on the project."
    fileprivate let graphLoaderContext: GraphLoaderContexting
    fileprivate let commandsContext: CommandsContexting
    fileprivate let graphLoader: GraphLoading
    fileprivate let workspaceGenerator: WorkspaceGenerating

    /// Path argument.
    let pathArgument: OptionArgument<String>

    /// Initializes the generate command with the argument parser.
    ///
    /// - Parameter parser: argument parser.
    public required convenience init(parser: ArgumentParser) {
        self.init(graphLoaderContext: GraphLoaderContext(),
                  commandsContext: CommandsContext(),
                  graphLoader: GraphLoader(),
                  workspaceGenerator: WorkspaceGenerator(),
                  parser: parser)
    }

    /// Initializes the command with the printer and the graph loading context.
    ///
    /// - Parameters:
    ///   - graphLoaderContext: graph loading context.
    ///   - commandsContext: commands context.
    ///   - graphLoader: graph loader.
    ///   - workspaceGenerator: workspace generator,
    ///   - parser: argument parser.
    init(graphLoaderContext: GraphLoaderContexting,
         commandsContext: CommandsContexting,
         graphLoader: GraphLoading,
         workspaceGenerator: WorkspaceGenerating,
         parser: ArgumentParser) {
        let subParser = parser.add(subparser: command, overview: overview)
        self.graphLoaderContext = graphLoaderContext
        self.commandsContext = commandsContext
        self.graphLoader = graphLoader
        self.workspaceGenerator = workspaceGenerator
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path where the Project.swift file will be generated",
                                     completion: .filename)
    }

    /// Runs the command.
    ///
    /// - Parameter _: argument parser arguments.
    /// - Throws: an error if the command cannot be executed.
    public func run(with arguments: ArgumentParser.Result) throws {
        var path: AbsolutePath! = arguments.get(pathArgument).map({ AbsolutePath($0) })
        if path == nil {
            path = AbsolutePath.current
        }
        let context = try GeneratorContext(graph: graphLoader.load(path: path))
        try workspaceGenerator.generate(path: path, context: context)
        context.printer.print(section: "Generate command succeeded 🎉")
    }
}
