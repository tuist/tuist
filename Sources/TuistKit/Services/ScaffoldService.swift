import TSCBasic
import TuistCore
import TuistLoader
import TuistScaffold
import TuistSupport

enum ScaffoldServiceError: FatalError, Equatable {
    var type: ErrorType {
        switch self {
        case .templateNotFound, .nonEmptyDirectory, .attributeNotProvided:
            return .abort
        }
    }

    case templateNotFound(String)
    case nonEmptyDirectory(AbsolutePath)
    case attributeNotProvided(String)

    var description: String {
        switch self {
        case let .templateNotFound(template):
            return "Could not find template \(template). Make sure it exists at Tuist/Templates/\(template)"
        case let .nonEmptyDirectory(path):
            return "Can't generate a template in the non-empty directory at path \(path.pathString)."
        case let .attributeNotProvided(name):
            return "You must provide \(name) option. Add --\(name) desired_value to your command."
        }
    }
}

class ScaffoldService {
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

    func run(path: String?,
             templateName: String,
             requiredTemplateOptions: [String: String],
             optionalTemplateOptions: [String: String?]) throws
    {
        let path = self.path(path)

        let templateDirectories = try templatesDirectoryLocator.templateDirectories(at: path)

        let templateDirectory = try self.templateDirectory(templateDirectories: templateDirectories,
                                                           template: templateName)

        let template = try templateLoader.loadTemplate(at: templateDirectory)

        let parsedAttributes = try parseAttributes(requiredTemplateOptions: requiredTemplateOptions,
                                                   optionalTemplateOptions: optionalTemplateOptions,
                                                   template: template)

        try templateGenerator.generate(template: template,
                                       to: path,
                                       attributes: parsedAttributes)

        logger.notice("Template \(templateName) was successfully generated", metadata: .success)
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    /// Parses all `attributes` from `template`
    /// If those attributes are optional, they default to `default` if not provided
    /// - Returns: Array of parsed attributes
    private func parseAttributes(requiredTemplateOptions: [String: String],
                                 optionalTemplateOptions: [String: String?],
                                 template: Template) throws -> [String: String]
    {
        try template.attributes.reduce(into: [:]) { attributesDictionary, attribute in
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
        else { throw ScaffoldServiceError.templateNotFound(template) }
        return templateDirectory
    }
}
