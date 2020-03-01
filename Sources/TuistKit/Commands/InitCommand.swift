import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport
import TuistTemplate

private typealias Platform = TuistCore.Platform
private typealias Product = TuistCore.Product

enum InitCommandError: FatalError, Equatable {
    case ungettableProjectName(AbsolutePath)
    case nonEmptyDirectory(AbsolutePath)
    case templateNotFound(String)

    var type: ErrorType {
        .abort
    }

    var description: String {
        switch self {
        case let .ungettableProjectName(path):
            return "Couldn't infer the project name from path \(path.pathString)."
        case let .nonEmptyDirectory(path):
            return "Can't initialize a project in the non-empty directory at path \(path.pathString)."
        case let .templateNotFound(template):
            return "Could not find template \(template)"
        }
    }

    static func == (lhs: InitCommandError, rhs: InitCommandError) -> Bool {
        switch (lhs, rhs) {
        case let (.ungettableProjectName(lhsPath), .ungettableProjectName(rhsPath)):
            return lhsPath == rhsPath
        case let (.nonEmptyDirectory(lhsPath), .nonEmptyDirectory(rhsPath)):
            return lhsPath == rhsPath
        case let (.templateNotFound(lhsTemplate), .templateNotFound(rhsTemplate)):
            return lhsTemplate == rhsTemplate
        default:
            return false
        }
    }
}

// swiftlint:disable:next type_body_length
class InitCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "init"
    static let overview = "Bootstraps a project."
    let platformArgument: OptionArgument<String>
    let pathArgument: OptionArgument<String>
    let nameArgument: OptionArgument<String>
    private let templateArgument: OptionArgument<String>
    private let attributesArgument: OptionArgument<[String]>
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateGenerator: TemplateGenerating

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  templatesDirectoryLocator: TemplatesDirectoryLocator(),
                  templateGenerator: TemplateGenerator())
    }

    init(parser: ArgumentParser,
         templatesDirectoryLocator: TemplatesDirectoryLocating,
         templateGenerator: TemplateGenerating) {
        let subParser = parser.add(subparser: InitCommand.command, overview: InitCommand.overview)
        platformArgument = subParser.add(option: "--platform",
                                         shortName: nil,
                                         kind: String.self,
                                         usage: "The platform (ios, tvos or macos) the product will be for (Default: ios).",
                                         completion: ShellCompletion.values([
                                             (value: "ios", description: "iOS platform"),
                                             (value: "tvos", description: "tvOS platform"),
                                             (value: "macos", description: "macOS platform"),
                                         ]))
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the folder where the project will be generated (Default: Current directory).",
                                     completion: .filename)
        nameArgument = subParser.add(option: "--name",
                                     shortName: "-n",
                                     kind: String.self,
                                     usage: "The name of the project. If it's not passed (Default: Name of the directory).",
                                     completion: nil)
        templateArgument = subParser.add(option: "--template",
                                         shortName: "-t",
                                         kind: String.self,
                                         usage: "The name of the template to use (you can list available templates with tuist scaffold --list).",
                                         completion: nil)
        attributesArgument = subParser.add(option: "--attributes",
                                           shortName: "-a",
                                           kind: [String].self,
                                           strategy: .remaining,
                                           usage: "Attributes for a given template",
                                           completion: nil)
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateGenerator = templateGenerator
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let platform = try self.platform(arguments: arguments)
        let path = try self.path(arguments: arguments)
        let name = try self.name(arguments: arguments, path: path)
        try verifyDirectoryIsEmpty(path: path)
        
        let directories = try templatesDirectoryLocator.templateDirectories(at: FileHandler.shared.currentPath)
        if let template = arguments.get(templateArgument) {
            guard
                let templateDirectory = directories.first(where: { $0.basename == template })
            else { throw InitCommandError.templateNotFound(template) }
            try templateGenerator.generate(at: templateDirectory,
                                           to: path,
                                           attributes: arguments.get(attributesArgument) ?? [])
        } else {
            guard
                let templateDirectory = directories.first(where: { $0.basename == "default" })
            else { throw InitCommandError.templateNotFound("default") }
            try templateGenerator.generate(at: templateDirectory,
                                           to: path,
                                           attributes: ["--name", name, "--platform", platform.rawValue])
        }
        
        Printer.shared.print(success: "Project generated at path \(path.pathString).")
    }

    // MARK: - Fileprivate

    /// Checks if the given directory is empty, essentially that it doesn't contain any file or directory.
    ///
    /// - Parameter path: Directory to be checked.
    /// - Throws: An InitCommandError.nonEmptyDirectory error when the directory is not empty.
    private func verifyDirectoryIsEmpty(path: AbsolutePath) throws {
        if !path.glob("*").isEmpty {
            throw InitCommandError.nonEmptyDirectory(path)
        }
    }
    
    private func name(arguments: ArgumentParser.Result, path: AbsolutePath) throws -> String {
        if let name = arguments.get(nameArgument) {
            return name
        } else if let name = path.components.last {
            return name
        } else {
            throw InitCommandError.ungettableProjectName(AbsolutePath.current)
        }
    }

    private func path(arguments: ArgumentParser.Result) throws -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func platform(arguments: ArgumentParser.Result) throws -> Platform {
        if let platformString = arguments.get(platformArgument) {
            if let platform = Platform(rawValue: platformString) {
                return platform
            } else {
                throw ArgumentParserError.invalidValue(argument: "platform", error: .custom("Platform should be either ios, tvos, or macos"))
            }
        } else {
            return .iOS
        }
    }
}
