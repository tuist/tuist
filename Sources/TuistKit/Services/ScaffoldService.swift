import Basic
import TuistCore
import TuistSupport
import TuistLoader
import TuistScaffold

class ScaffoldService {
    private let templateLoader: TemplateLoading
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateGenerator: TemplateGenerating
    
    init(templateLoader: TemplateLoading = TemplateLoader(),
         templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
         templateGenerator: TemplateGenerating = TemplateGenerator()) {
        self.templateLoader = templateLoader
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateGenerator = templateGenerator
    }
    
    func loadTemplateOptions(templateName: String,
                             path: String?) throws -> (required: [String],
                                                       optional: [(name: String, default: String)]) {
        let path = self.path(path)
        let directories = try templatesDirectoryLocator.templateDirectories(at: path)

        let templateDirectory = try self.templateDirectory(templateDirectories: directories,
                                                           template: templateName)

        let template = try templateLoader.loadTemplate(at: templateDirectory)
        
        return template.attributes.reduce(into: (required: [], optional: [])) { currentValue, attribute in
            switch attribute {
            case let .optional(name, default: defaultValue):
                currentValue.optional.append((name: name, default: defaultValue))
            case let .required(name):
                currentValue.required.append(name)
            }
        }
    }
    
    func run(path: String?,
             templateName: String,
             requiredTemplateOptions: [String: String],
             optionalTemplateOptions: [String: String?]) throws {
        let path = self.path(path)

        let templateDirectories = try templatesDirectoryLocator.templateDirectories(at: path)

        let templateDirectory = try self.templateDirectory(templateDirectories: templateDirectories,
                                                          template: templateName)

        let template = try templateLoader.loadTemplate(at: templateDirectory)

        let parsedAttributes = try validateAttributes(requiredTemplateOptions: requiredTemplateOptions,
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

    /// Validates if all `attributes` from `template` have been provided
    /// If those attributes are optional, they default to `default` if not provided
    /// - Returns: Array of parsed attributes
    private func validateAttributes(requiredTemplateOptions: [String: String],
                                    optionalTemplateOptions: [String: String?],
                                    template: Template) throws -> [String: String] {
        try template.attributes.reduce(into: [:]) { attributesDictionary, attribute in
            switch attribute {
            case let .required(name):
                guard
                    let option = requiredTemplateOptions[name]
                else { throw ScaffoldCommandError.attributeNotProvided(name) }
                attributesDictionary[name] = option
            case let .optional(name, default: defaultValue):
                guard
                    let option = optionalTemplateOptions[name]
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
        else { throw ScaffoldCommandError.templateNotFound(template) }
        return templateDirectory
    }
}
