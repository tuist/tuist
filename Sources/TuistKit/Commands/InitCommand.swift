import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistGenerator
import TuistLoader
import TuistScaffold
import TuistSupport

private typealias Platform = TuistCore.Platform
private typealias Product = TuistCore.Product

enum InitCommandError: FatalError, Equatable {
    case ungettableProjectName(AbsolutePath)
    case nonEmptyDirectory(AbsolutePath)
    case templateNotFound(String)
    case templateNotProvided
    case attributeNotProvided(String)

    var type: ErrorType {
        .abort
    }

    var description: String {
        switch self {
        case let .templateNotFound(template):
            return "Could not find template \(template). Make sure it exists at Tuist/Templates/\(template)"
        case .templateNotProvided:
            return "You must provide template name"
        case let .ungettableProjectName(path):
            return "Couldn't infer the project name from path \(path.pathString)."
        case let .nonEmptyDirectory(path):
            return "Can't initialize a project in the non-empty directory at path \(path.pathString)."
        case let .attributeNotProvided(name):
            return "You must provide \(name) option. Add --\(name) desired_value to your command."
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
        case (.templateNotProvided, .templateNotProvided):
            return true
        default:
            return false
        }
    }
}

class InitCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "init"
    static let overview = "Bootstraps a project."
    private let platformArgument: OptionArgument<String>
    private let pathArgument: OptionArgument<String>
    private let nameArgument: OptionArgument<String>
    private let templateArgument: OptionArgument<String>
    private var attributesArguments: [String: OptionArgument<String>] = [:]
    private let subParser: ArgumentParser
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateGenerator: TemplateGenerating
    private let templateLoader: TemplateLoading

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  templatesDirectoryLocator: TemplatesDirectoryLocator(),
                  templateGenerator: TemplateGenerator(),
                  templateLoader: TemplateLoader())
    }

    init(parser: ArgumentParser,
         templatesDirectoryLocator: TemplatesDirectoryLocating,
         templateGenerator: TemplateGenerating,
         templateLoader: TemplateLoading) {
        subParser = parser.add(subparser: InitCommand.command, overview: InitCommand.overview)
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
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateGenerator = templateGenerator
        self.templateLoader = templateLoader
    }

    func parse(with parser: ArgumentParser, arguments: [String]) throws -> ArgumentParser.Result {
        guard arguments.contains("--template") else { return try parser.parse(arguments) }
        // Plucking out path and template argument
        let pairedArguments = stride(from: 2, to: arguments.count, by: 2).map {
            arguments[$0 ..< min($0 + 2, arguments.count)]
        }
        let filteredArguments = pairedArguments
            .filter {
                $0.first == "--path" || $0.first == "--template"
            }
            .flatMap { Array($0) }
        // We want to parse only the name of template, not its arguments which will be dynamically added
        let resultArguments = try parser.parse(filteredArguments)

        guard let templateName = resultArguments.get(templateArgument) else { throw InitCommandError.templateNotProvided }

        let path = self.path(arguments: resultArguments)
        let directories = try templatesDirectoryLocator.templateDirectories(at: path)

        let templateDirectory = try self.templateDirectory(templateDirectories: directories,
                                                           template: templateName)

        let template = try templateLoader.loadTemplate(at: templateDirectory)

        // Dynamically add attributes from template to `subParser`
        attributesArguments = template.attributes.reduce([:]) {
            var mutableDictionary = $0
            mutableDictionary[$1.name] = subParser.add(option: "--\($1.name)",
                                                       kind: String.self)
            return mutableDictionary
        }

        return try parser.parse(arguments)
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let platform = try self.platform(arguments: arguments)
        let path = self.path(arguments: arguments)
        let name = try self.name(arguments: arguments, path: path)
        try verifyDirectoryIsEmpty(path: path)

        let directories = try templatesDirectoryLocator.templateDirectories(at: path)
        if let template = arguments.get(templateArgument) {
            guard
                let templateDirectory = directories.first(where: { $0.basename == template })
            else { throw InitCommandError.templateNotFound(template) }
            let template = try templateLoader.loadTemplate(at: templateDirectory)
            let parsedAttributes = try validateAttributes(attributesArguments,
                                                          template: template,
                                                          arguments: arguments)

            try templateGenerator.generate(template: template,
                                           to: path,
                                           attributes: parsedAttributes)
        } else {
            guard
                let templateDirectory = directories.first(where: { $0.basename == "default" })
            else { throw InitCommandError.templateNotFound("default") }
            let template = try templateLoader.loadTemplate(at: templateDirectory)
            try templateGenerator.generate(template: template,
                                           to: path,
                                           attributes: ["name": name, "platform": platform.caseValue])
        }

        logger.notice("Project generated at path \(path.pathString).", metadata: .success)
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

    /// Validates if all `attributes` from `template` have been provided
    /// If those attributes are optional, they default to `default` if not provided
    /// - Returns: Array of parsed attributes
    private func validateAttributes(_ attributes: [String: OptionArgument<String>],
                                    template: Template,
                                    arguments: ArgumentParser.Result) throws -> [String: String] {
        try template.attributes.reduce([:]) {
            var mutableDict = $0
            switch $1 {
            case let .required(name):
                guard
                    let argument = attributes[name],
                    let value = arguments.get(argument)
                else { throw InitCommandError.attributeNotProvided(name) }
                mutableDict[name] = value
            case let .optional(name, default: defaultValue):
                guard
                    let argument = attributes[name],
                    let value: String = arguments.get(argument)
                else {
                    mutableDict[name] = defaultValue
                    return mutableDict
                }
                mutableDict[name] = value
            }
            return mutableDict
        }
    }

    /// Finds template directory
    /// - Parameters:
    ///     - templateDirectories: Paths of available templates
    ///     - template: Name of template
    /// - Returns: `AbsolutePath` of template directory
    private func templateDirectory(templateDirectories: [AbsolutePath], template: String) throws -> AbsolutePath {
        guard
            let templateDirectory = templateDirectories.first(where: { $0.basename == template })
        else { throw InitCommandError.templateNotFound(template) }
        return templateDirectory
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

    private func path(arguments: ArgumentParser.Result) -> AbsolutePath {
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
