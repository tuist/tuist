import Basic
import Foundation
import Utility

enum GenerateCommandError: Error, ErrorStringConvertible, Equatable {
    static func == (_: GenerateCommandError, _: GenerateCommandError) -> Bool {
        return true
    }

    var errorDescription: String {
        return ""
    }
}

public class GenerateCommand: NSObject, Command {
    /// Command name.
    public let command = "generate"

    /// Command description.
    public let overview = "Generates an Xcode workspace to start working on the project."

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
        let subParser = parser.add(subparser: command, overview: overview)
        self.graphLoaderContext = graphLoaderContext
        self.graphLoader = graphLoader
        self.workspaceGenerator = workspaceGenerator
        self.context = context
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
    public func run(with arguments: ArgumentParser.Result) {
        context.errorHandler.try {
            var path: AbsolutePath! = arguments.get(pathArgument).map({ AbsolutePath($0) })
            if path == nil {
                path = AbsolutePath.current
            }
            let context = try GeneratorContext(graph: graphLoader.load(path: path))
            try workspaceGenerator.generate(path: path, context: context)
            self.context.printer.print(section: "Generate command succeeded 🎉")
        }
    }
}
