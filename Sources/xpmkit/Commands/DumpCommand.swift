import Basic
import Foundation
import Utility
import xpmcore

enum DumpCommandError: FatalError, Equatable {
    case manifestNotFound(AbsolutePath)
    var description: String {
        switch self {
        case let .manifestNotFound(path):
            return "Couldn't find Project.swift, Workspace.swift, or Config.swift in the directory \(path.asString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .manifestNotFound:
            return .abort
        }
    }

    static func == (lhs: DumpCommandError, rhs: DumpCommandError) -> Bool {
        switch (lhs, rhs) {
        case let (.manifestNotFound(lhsPath), .manifestNotFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

class DumpCommand: NSObject, Command {

    // MARK: - Attributes

    static let command = "dump"
    static let overview = "Prints parsed Project.swift, Workspace.swift, or Config.swift as JSON."
    fileprivate let graphLoaderContext: GraphLoaderContexting
    fileprivate let context: CommandsContexting
    let pathArgument: OptionArgument<String>

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(graphLoaderContext: GraphLoaderContext(),
                  context: CommandsContext(),
                  parser: parser)
    }

    init(graphLoaderContext: GraphLoaderContexting,
         context: CommandsContexting,
         parser: ArgumentParser) {
        let subParser = parser.add(subparser: DumpCommand.command, overview: DumpCommand.overview)
        self.graphLoaderContext = graphLoaderContext
        self.context = context
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path where the Project.swift file will be generated",
                                     completion: .filename)
    }

    // MARK: - Command

    func run(with arguments: ArgumentParser.Result) throws {
        var path: AbsolutePath!
        if let argumentPath = arguments.get(pathArgument) {
            path = AbsolutePath(argumentPath, relativeTo: AbsolutePath.current)
        } else {
            path = AbsolutePath.current
        }
        let projectPath = path.appending(component: Constants.Manifest.project)
        let workspacePath = path.appending(component: Constants.Manifest.workspace)
        var json: JSON!
        if graphLoaderContext.fileHandler.exists(projectPath) {
            json = try graphLoaderContext.manifestLoader.load(path: projectPath, context: graphLoaderContext)
        } else if graphLoaderContext.fileHandler.exists(workspacePath) {
            json = try graphLoaderContext.manifestLoader.load(path: workspacePath, context: graphLoaderContext)
        } else {
            throw DumpCommandError.manifestNotFound(path)
        }
        context.printer.print(json.toString(prettyPrint: true))
    }
}
