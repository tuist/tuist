import Foundation
import TSCBasic
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistScaffold
import TuistSupport

class ListService {
    // MARK: - OutputFormat

    enum OutputFormat {
        case table
        case json
    }

    private let configLoader: ConfigLoading
    private let pluginService: PluginServicing
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateLoader: TemplateLoading

    init(
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        pluginService: PluginServicing = PluginService(),
        templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
        templateLoader: TemplateLoading = TemplateLoader()
    ) {
        self.configLoader = configLoader
        self.pluginService = pluginService
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateLoader = templateLoader
    }

    func run(path: String?, outputFormat format: OutputFormat) async throws {
        let path = try self.path(path)

        let plugins = try await loadPlugins(at: path)
        let templateDirectories = try locateTemplateDirectories(at: path, plugins: plugins)
        let templates: [PrintableTemplate] = try templateDirectories.map { path in
            let template = try templateLoader.loadTemplate(at: path)
            return PrintableTemplate(name: path.basename, description: template.description)
        }

        let output = try string(for: templates, in: format)
        logger.info("\(output)")
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path = path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func string(
        for templates: [PrintableTemplate],
        in format: ListService.OutputFormat
    ) throws -> String {
        switch format {
        case .table:
            let textTable = TextTable<PrintableTemplate> { [
                TextTable.Column(title: "Name", value: $0.name),
                TextTable.Column(title: "Description", value: $0.description),
            ] }
            return textTable.render(templates)

        case .json:
            let json = try templates.toJSON()
            return json.toString(prettyPrint: true)
        }
    }

    private func loadPlugins(at path: AbsolutePath) async throws -> Plugins {
        let config = try configLoader.loadConfig(path: path)
        return try await pluginService.loadPlugins(using: config)
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
}

private struct PrintableTemplate: Codable {
    let name: String
    let description: String
}
