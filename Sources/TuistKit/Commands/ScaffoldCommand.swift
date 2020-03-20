import Basic
import Foundation
import SPMUtility
import TuistLoader
import TuistScaffold
import TuistSupport

enum ScaffoldCommandError: FatalError, Equatable {
    var type: ErrorType { .abort }

    case templateNotFound(String)
    case templateNotProvided
    case nonEmptyDirectory(AbsolutePath)

    var description: String {
        switch self {
        case let .templateNotFound(template):
            return "Could not find template \(template). Make sure it exists at Tuist/Templates/\(template)"
        case .templateNotProvided:
            return "You must provide template name"
        case let .nonEmptyDirectory(path):
            return "Can't generate a template in the non-empty directory at path \(path.pathString)."
        }
    }
}

class ScaffoldCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "scaffold"
    static let overview = "Generates new project based on template."
    private let listArgument: OptionArgument<Bool>
    private let pathArgument: OptionArgument<String>
    private let templateArgument: PositionalArgument<String>
    private var attributesArguments: [String: OptionArgument<String>] = [:]
    private let subParser: ArgumentParser

    private let templateLoader: TemplateLoading
    private let templatesDirectoryLocator: TemplatesDirectoryLocating

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  templateLoader: TemplateLoader(),
                  templatesDirectoryLocator: TemplatesDirectoryLocator())
    }

    init(parser: ArgumentParser,
         templateLoader: TemplateLoading,
         templatesDirectoryLocator: TemplatesDirectoryLocating) {
        subParser = parser.add(subparser: ScaffoldCommand.command, overview: ScaffoldCommand.overview)
        listArgument = subParser.add(option: "--list",
                                     shortName: "-l",
                                     kind: Bool.self,
                                     usage: "Lists available scaffold templates",
                                     completion: nil)
        templateArgument = subParser.add(positional: "template",
                                         kind: String.self,
                                         optional: true,
                                         usage: "Name of template you want to use",
                                         completion: nil)
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the folder where the template will be generated (Default: Current directory).",
                                     completion: .filename)
        self.templateLoader = templateLoader
        self.templatesDirectoryLocator = templatesDirectoryLocator
    }

    func parse(with parser: ArgumentParser, arguments: [String]) throws -> ArgumentParser.Result {
        guard arguments.count >= 2 else { throw ScaffoldCommandError.templateNotProvided }
        // We want to parse only the name of template, not its arguments which will be dynamically added
        let resultArguments = try parser.parse(Array(arguments.prefix(2)))

        if resultArguments.get(listArgument) != nil {
            return try parser.parse(arguments)
        }

        guard let templateName = resultArguments.get(templateArgument) else { throw ScaffoldCommandError.templateNotProvided }

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
        logger.warning("Scaffold is a feature that is currently being worked on")

        guard let template = arguments.get(templateArgument) else { throw ScaffoldCommandError.templateNotProvided }

        let path = self.path(arguments: arguments)
        let templateDirectories = try templatesDirectoryLocator.templateDirectories(at: path)

        let shouldList = arguments.get(listArgument) ?? false
        if shouldList {
            try templateDirectories.forEach {
                let template = try templateLoader.loadTemplate(at: $0)
                logger.info("\($0.basename): \(template.description)")
            }
            return
        }

        try verifyDirectoryIsEmpty(path: path)

        _ = try templateDirectory(templateDirectories: templateDirectories,
                                  template: template)

        // TODO: Generate templates

        logger.notice("Template \(template) was successfully generated", metadata: .success)
    }

    // MARK: - Helpers

    private func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    /// Checks if the given directory is empty, essentially that it doesn't contain any file or directory.
    ///
    /// - Parameter path: Directory to be checked.
    /// - Throws: An ScaffoldCommandError.nonEmptyDirectory error when the directory is not empty.
    private func verifyDirectoryIsEmpty(path: AbsolutePath) throws {
        if !path.glob("*").isEmpty {
            throw ScaffoldCommandError.nonEmptyDirectory(path)
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
        else { throw ScaffoldCommandError.templateNotFound(template) }
        return templateDirectory
    }
}
