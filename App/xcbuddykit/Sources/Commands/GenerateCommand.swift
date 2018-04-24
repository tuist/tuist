import Basic
import Foundation
import Utility

enum GenerateCommandError: Error, CustomStringConvertible, Equatable {
    static func ==(lhs: GenerateCommandError, rhs: GenerateCommandError) -> Bool {
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
    
    /// Path argument.
    let pathArgument: OptionArgument<String>
    
    /// Initializes the generate command with the argument parser.
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
       
    }
}
