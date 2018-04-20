import Basic
import Foundation
import Sparkle
import Utility

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

    /// Initializes the dump command with the argument parser.
    ///
    /// - Parameter parser: argument parser.
    public required init(parser: ArgumentParser) {
        parser.add(subparser: command, overview: overview)
        graphLoaderContext = GraphLoaderContext(projectPath: AbsolutePath.current)
        commandsContext = CommandsContext()
    }

    /// Initializes the command with the printer and the graph loading context.
    ///
    /// - Parameters:
    ///   - graphLoaderContext: graph loading context.
    ///   - commandsContext: commands context.
    init(graphLoaderContext: GraphLoaderContexting,
         commandsContext: CommandsContexting) {
        self.graphLoaderContext = graphLoaderContext
        self.commandsContext = commandsContext
    }

    /// Runs the command.
    ///
    /// - Parameter _: argument parser arguments.
    /// - Throws: an error if the command cannot be executed.
    public func run(with _: ArgumentParser.Result) throws {
        do {
            let path = AbsolutePath.current
            if !graphLoaderContext.fileHandler.exists(path) {
                throw "Path \(path.asString) doesn't exist"
            }
            let json: JSON = try graphLoaderContext.manifestLoader.load(path: path, context: graphLoaderContext)
            commandsContext.printer.print(json.toString(prettyPrint: true))
        } catch {
            commandsContext.printer.print(error.localizedDescription)
        }
    }
}
