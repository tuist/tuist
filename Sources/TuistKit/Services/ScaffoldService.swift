import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistScaffold
import TuistSupport

enum ScaffoldServiceError: FatalError, Equatable {
    var type: ErrorType {
        switch self {
        case .templateNotFound, .nonEmptyDirectory, .attributeNotProvided:
            return .abort
        }
    }

    case templateNotFound(String, searchPaths: [AbsolutePath])
    case nonEmptyDirectory(AbsolutePath)
    case attributeNotProvided(String)

    var description: String {
        switch self {
        case let .templateNotFound(template, searchPaths):
            let searchDirectories = searchPaths
                .reduce(into: Set<AbsolutePath>()) { result, path in result.insert(path.parentDirectory) }
                .reduce("\n") { $0 + "  * \($1.pathString)\n" }
            return "Could not find template \(template) in: \(searchDirectories)"
        case let .nonEmptyDirectory(path):
            return "Can't generate a template in the non-empty directory at path \(path.pathString)."
        case let .attributeNotProvided(name):
            return "You must provide \(name) option. Add --\(name) desired_value to your command."
        }
    }
}

final class ScaffoldService {
    private let templateLoader: TemplateLoading
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateGenerator: TemplateGenerating
    private let configLoader: ConfigLoading
    private let pluginService: PluginServicing

    init(
        templateLoader: TemplateLoading = TemplateLoader(),
        templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
        templateGenerator: TemplateGenerating = TemplateGenerator(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        pluginService: PluginServicing = PluginService()
    ) {
        self.templateLoader = templateLoader
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateGenerator = templateGenerator
        self.configLoader = configLoader
        self.pluginService = pluginService
    }

    func loadTemplateOptions(
        templateName: String,
        path: String?
    ) async throws -> (required: [String], optional: [String]) {
        let path = try self.path(path)
        let plugins = try await loadPlugins(at: path)
        let templateDirectories = try locateTemplateDirectories(at: path, plugins: plugins)
        let templateDirectory = try templateDirectory(
            templateDirectories: templateDirectories,
            template: templateName
        )

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

    func run(
        path: String?,
        templateName: String,
        requiredTemplateOptions: [String: String],
        optionalTemplateOptions: [String: String?]
    ) async throws {
        let path = try self.path(path)
        let plugins = try await loadPlugins(at: path)
        let templateDirectories = try locateTemplateDirectories(at: path, plugins: plugins)

        let templateDirectory = try templateDirectory(
            templateDirectories: templateDirectories,
            template: templateName
        )

        let template = try templateLoader.loadTemplate(at: templateDirectory)

        let parsedAttributes = try parseAttributes(
            requiredTemplateOptions: requiredTemplateOptions,
            optionalTemplateOptions: optionalTemplateOptions,
            template: template
        )

        try templateGenerator.generate(
            template: template,
            to: path,
            attributes: parsedAttributes
        )

        logger.notice("Template \(templateName) was successfully generated", metadata: .success)
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path = path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func loadPlugins(at path: AbsolutePath) async throws -> Plugins {
        let config = try configLoader.loadConfig(path: path)
        return try await pluginService.loadPlugins(using: config)
    }

    /// Parses all `attributes` from `template`
    /// If those attributes are optional, they default to `default` if not provided
    /// - Returns: Array of parsed attributes
    private func parseAttributes(
        requiredTemplateOptions: [String: String],
        optionalTemplateOptions: [String: String?],
        template: Template
    ) throws -> [String: String] {
        try template.attributes.reduce(into: [:]) { attributesDictionary, attribute in
            switch attribute {
            case let .required(name):
                guard let option = requiredTemplateOptions[name]
                else { throw ScaffoldServiceError.attributeNotProvided(name) }
                attributesDictionary[name] = option
            case let .optional(name, default: defaultValue):
                guard let unwrappedOption = optionalTemplateOptions[name],
                      let option = unwrappedOption
                else {
                    attributesDictionary[name] = defaultValue
                    return
                }
                attributesDictionary[name] = option
            }
        }
    }

    /// Locates all template directories, local, system, and plugin.
    /// - Parameter path: The path where the command is being executed.
    /// - Returns: A list of template directories
    private func locateTemplateDirectories(
        at path: AbsolutePath,
        plugins: Plugins
    ) throws -> [AbsolutePath] {
        let templateRelativeDirectories = try templatesDirectoryLocator.templateDirectories(at: path)
        let templatePluginDirectories = plugins.templateDirectories
        return templateRelativeDirectories + templatePluginDirectories
    }

    /// Finds template directory
    /// - Parameters:
    ///     - templateDirectories: Paths of available templates
    ///     - template: Name of template
    /// - Returns: `AbsolutePath` of template directory
    private func templateDirectory(templateDirectories: [AbsolutePath], template: String) throws -> AbsolutePath {
        guard let templateDirectory = templateDirectories.first(where: { $0.basename == template })
        else { throw ScaffoldServiceError.templateNotFound(template, searchPaths: templateDirectories) }
        return templateDirectory
    }
}
