import TSCBasic
import TuistCore
import TuistLoader
import TuistScaffold
import TuistSupport

enum InitServiceError: FatalError, Equatable {
    case ungettableProjectName(AbsolutePath)
    case nonEmptyDirectory(AbsolutePath)
    case templateNotFound(String)
    case templateNotProvided
    case attributeNotProvided(String)
    case invalidValue(argument: String, error: String)

    var type: ErrorType {
        switch self {
        case .ungettableProjectName, .nonEmptyDirectory, .templateNotFound, .templateNotProvided, .attributeNotProvided, .invalidValue:
            return .abort
        }
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
        case let .invalidValue(argument: argument, error: error):
            return "\(error) for argument \(argument); use --help to print usage"
        }
    }
}

class InitService {
    private let templateLoader: TemplateLoading
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateGenerator: TemplateGenerating

    init(templateLoader: TemplateLoading = TemplateLoader(),
         templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
         templateGenerator: TemplateGenerating = TemplateGenerator())
    {
        self.templateLoader = templateLoader
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateGenerator = templateGenerator
    }

    func loadTemplateOptions(templateName: String,
                             path: String?) throws -> (required: [String],
                                                       optional: [String])
    {
        let path = self.path(path)
        let directories = try templatesDirectoryLocator.templateDirectories(at: path)

        let templateDirectory = try self.templateDirectory(templateDirectories: directories,
                                                           template: templateName)

        let template = try templateLoader.loadTemplate(at: templateDirectory)

        return template.attributes.reduce(into: (required: [], optional: [])) { currentValue, attribute in
            switch attribute {
            case let .optional(name, default: _):
                currentValue.optional.append(name)
            case let .required(name):
                currentValue.required.append(name)
            }
        }
    }

    func run(name: String?,
             platform: String?,
             path: String?,
             templateName: String?,
             requiredTemplateOptions: [String: String],
             optionalTemplateOptions: [String: String?]) throws
    {
        let platform = try self.platform(platform)
        let path = self.path(path)
        let name = try self.name(name, path: path)
        try verifyDirectoryIsEmpty(path: path)

        let directories = try templatesDirectoryLocator.templateDirectories(at: path)
        if let templateName = templateName {
            guard
                let templateDirectory = directories.first(where: { $0.basename == templateName })
            else { throw InitServiceError.templateNotFound(templateName) }
            let template = try templateLoader.loadTemplate(at: templateDirectory)
            let parsedAttributes = try parseAttributes(name: name,
                                                       platform: platform,
                                                       requiredTemplateOptions: requiredTemplateOptions,
                                                       optionalTemplateOptions: optionalTemplateOptions,
                                                       template: template)

            try templateGenerator.generate(template: template,
                                           to: path,
                                           attributes: parsedAttributes)
        } else {
            guard
                let templateDirectory = directories.first(where: { $0.basename == "default" })
            else { throw InitServiceError.templateNotFound("default") }
            let template = try templateLoader.loadTemplate(at: templateDirectory)
            try templateGenerator.generate(template: template,
                                           to: path,
                                           attributes: ["name": name, "platform": platform.caseValue])
        }

        logger.notice("Project generated at path \(path.pathString).", metadata: .success)
    }

    // MARK: - Helpers

    /// Checks if the given directory is empty, essentially that it doesn't contain any file or directory.
    ///
    /// - Parameter path: Directory to be checked.
    /// - Throws: An InitServiceError.nonEmptyDirectory error when the directory is not empty.
    private func verifyDirectoryIsEmpty(path: AbsolutePath) throws {
        if !path.glob("*").isEmpty {
            throw InitServiceError.nonEmptyDirectory(path)
        }
    }

    /// Parses all `attributes` from `template`
    /// If those attributes are optional, they default to `default` if not provided
    /// - Returns: Array of parsed attributes
    private func parseAttributes(name: String,
                                 platform: Platform,
                                 requiredTemplateOptions: [String: String],
                                 optionalTemplateOptions: [String: String?],
                                 template: Template) throws -> [String: String]
    {
        try template.attributes.reduce(into: [:]) { attributesDictionary, attribute in
            if attribute.name == "name" {
                attributesDictionary[attribute.name] = name
                return
            }
            if attribute.name == "platform" {
                attributesDictionary[attribute.name] = platform.caseValue
                return
            }
            switch attribute {
            case let .required(name):
                guard
                    let option = requiredTemplateOptions[name]
                else { throw ScaffoldServiceError.attributeNotProvided(name) }
                attributesDictionary[name] = option
            case let .optional(name, default: defaultValue):
                guard
                    let unwrappedOption = optionalTemplateOptions[name],
                    let option = unwrappedOption
                else {
                    attributesDictionary[name] = defaultValue
                    return
                }
                attributesDictionary[name] = option
            }
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
        else { throw InitServiceError.templateNotFound(template) }
        return templateDirectory
    }

    private func name(_ name: String?, path: AbsolutePath) throws -> String {
        if let name = name {
            return name
        } else if let name = path.components.last {
            return name
        } else {
            throw InitServiceError.ungettableProjectName(AbsolutePath.current)
        }
    }

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func platform(_ platform: String?) throws -> Platform {
        if let platformString = platform {
            if let platform = Platform(rawValue: platformString) {
                return platform
            } else {
                throw InitServiceError.invalidValue(argument: "platform", error: "Platform should be either ios, tvos, or macos")
            }
        } else {
            return .iOS
        }
    }
}
