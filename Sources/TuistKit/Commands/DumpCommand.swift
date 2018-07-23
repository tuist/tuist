import Basic
import Foundation
import TuistCore
import Utility

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

    // MARK: - Command

    static let command = "dump"
    static let overview = "Prints parsed Project.swift, Workspace.swift, or Config.swift as JSON."

    // MARK: - Attributes

    fileprivate let fileHandler: FileHandling
    fileprivate let manifestLoader: GraphManifestLoading
    fileprivate let printer: Printing
    let pathArgument: OptionArgument<String>

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(fileHandler: FileHandler(),
                  manifestLoader: GraphManifestLoader(),
                  printer: Printer(),
                  parser: parser)
    }

    init(fileHandler: FileHandling,
         manifestLoader: GraphManifestLoading,
         printer: Printing,
         parser: ArgumentParser) {
        let subParser = parser.add(subparser: DumpCommand.command, overview: DumpCommand.overview)
        self.fileHandler = fileHandler
        self.manifestLoader = manifestLoader
        self.printer = printer
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
        if fileHandler.exists(projectPath) {
            json = try manifestLoader.load(path: projectPath)
        } else if fileHandler.exists(workspacePath) {
            json = try manifestLoader.load(path: workspacePath)
        } else {
            throw DumpCommandError.manifestNotFound(path)
        }
        printer.print(json.toString(prettyPrint: true))
    }
}
