import Basic
import Foundation
import Sparkle
import Utility

/// Dump command error.
///
/// - manifestNotFound: thrown when the manifest cannot be found at the given path.
enum DumpCommandError: Error, CustomStringConvertible, Equatable {
    case manifestNotFound(AbsolutePath)
    var description: String {
        switch self {
        case let .manifestNotFound(path):
            return "Couldn't find Project.swift, Workspace.swift, or Config.swift in the directory \(path.asString)"
        }
    }

    static func == (lhs: DumpCommandError, rhs: DumpCommandError) -> Bool {
        switch (lhs, rhs) {
        case let (.manifestNotFound(lhsPath), .manifestNotFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

/// Command that dumps the manifest into the console.
public class DumpCommand: NSObject, Command, SPUUpdaterDelegate {
    /// Command name.
    public let command = "dump"

    // Command overview.
    public let overview = "Prints parsed Project.swift, Workspace.swift, or Config.swift as JSON."

    /// Graph loading context.
    fileprivate let graphLoaderContext: GraphLoaderContexting

    /// Commands context.
    fileprivate let commandsContext: CommandsContexting

    /// Path argument.
    let pathArgument: OptionArgument<String>

    /// Initializes the dump command with the argument parser.
    ///
    /// - Parameter parser: argument parser.
    public required convenience init(parser: ArgumentParser) {
        self.init(graphLoaderContext: GraphLoaderContext(),
                  commandsContext: CommandsContext(),
                  parser: parser)
    }

    /// Initializes the command with the printer and the graph loading context.
    ///
    /// - Parameters:
    ///   - graphLoaderContext: graph loading context.
    ///   - commandsContext: commands context.
    ///   - parser: argument parser.
    init(graphLoaderContext: GraphLoaderContexting,
         commandsContext: CommandsContexting,
         parser: ArgumentParser) {
        let subParser = parser.add(subparser: command, overview: overview)
        self.graphLoaderContext = graphLoaderContext
        self.commandsContext = commandsContext
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
        let projectPath = path.appending(component: Constants.Manifest.project)
        let workspacePath = path.appending(component: Constants.Manifest.workspace)
        let configPath = path.appending(component: Constants.Manifest.config)
        var json: JSON!
        if graphLoaderContext.fileHandler.exists(projectPath) {
            json = try graphLoaderContext.manifestLoader.load(path: projectPath, context: graphLoaderContext)
        } else if graphLoaderContext.fileHandler.exists(workspacePath) {
            json = try graphLoaderContext.manifestLoader.load(path: workspacePath, context: graphLoaderContext)
        } else if graphLoaderContext.fileHandler.exists(configPath) {
            json = try graphLoaderContext.manifestLoader.load(path: configPath, context: graphLoaderContext)
        } else {
            throw DumpCommandError.manifestNotFound(path)
        }
        commandsContext.printer.print(json.toString(prettyPrint: true))
    }
}
