import Foundation
import Path
import ServiceContextModule
import TuistCore
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
        let templateDirectories = try await locateTemplateDirectories(at: path, plugins: plugins)
        let templates: [PrintableTemplate] = try await templateDirectories.concurrentMap { path in
            let template = try await self.templateLoader.loadTemplate(at: path, plugins: plugins)
            return PrintableTemplate(name: path.basename, description: template.description)
        }

        try output(for: templates, in: format)
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func output(
        for templates: [PrintableTemplate],
        in format: ListService.OutputFormat
    ) throws {
        switch format {
        case .table:
            let textTable = TextTable<PrintableTemplate> { [
                TextTable.Column(title: "Name", value: $0.name),
                TextTable.Column(title: "Description", value: $0.description),
            ] }
            ServiceContext.current?.logger?.notice("\(textTable.render(templates))")

        case .json:
            let json = try templates.toJSON()
            ServiceContext.current?.logger?.notice("\(json.toString(prettyPrint: true))", metadata: .json)
        }
    }

    private func loadPlugins(at path: AbsolutePath) async throws -> Plugins {
        let config = try await configLoader.loadConfig(path: path)
        return try await pluginService.loadPlugins(using: config)
    }

    /// Locates all template directories, local, system, and plugin.
    /// - Parameter path: The path where the command is being executed.
    /// - Returns: A list of template directories
    private func locateTemplateDirectories(
        at path: AbsolutePath,
        plugins: Plugins
    ) async throws -> [AbsolutePath] {
        let templateRelativeDirectories = try await templatesDirectoryLocator.templateDirectories(at: path)
        let templatePluginDirectories = plugins.templateDirectories
        return templateRelativeDirectories + templatePluginDirectories
    }
}

private struct PrintableTemplate: Codable {
    let name: String
    let description: String
}
