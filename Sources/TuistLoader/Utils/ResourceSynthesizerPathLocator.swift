import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

protocol ResourceSynthesizerPathLocating {
    func templatePath(
        for pluginName: String,
        resourceName: String,
        resourceSynthesizerPlugins: [PluginResourceSynthesizer]
    ) throws -> AbsolutePath

    func templatePath(
        for resourceName: String,
        path: AbsolutePath
    ) -> AbsolutePath?
}

enum ResourceSynthesizerPathLocatorError: FatalError, Equatable {
    case pluginNotFound(String, [String])
    case resourceTemplateNotFound(name: String, plugin: String)

    var type: ErrorType {
        switch self {
        case .pluginNotFound,
             .resourceTemplateNotFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .pluginNotFound(name, availablePlugins):
            return "Plugin \(name) was not found. Available plugins: \(availablePlugins.joined(separator: ", "))"
        case let .resourceTemplateNotFound(name: name, plugin: pluginName):
            return "No template \(name) found in a plugin \(pluginName)"
        }
    }
}

final class ResourceSynthesizerPathLocator: ResourceSynthesizerPathLocating {
    private let rootDirectoryLocator: RootDirectoryLocating

    init(
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    func templatePath(
        for pluginName: String,
        resourceName: String,
        resourceSynthesizerPlugins: [PluginResourceSynthesizer]
    ) throws -> AbsolutePath {
        guard let plugin = resourceSynthesizerPlugins.first(where: { $0.name == pluginName })
        else { throw ResourceSynthesizerPathLocatorError.pluginNotFound(pluginName, resourceSynthesizerPlugins.map(\.name)) }

        let resourceTemplatePath = plugin.path
            .appending(components: "\(resourceName).stencil")
        guard FileHandler.shared.exists(resourceTemplatePath)
        else {
            throw ResourceSynthesizerPathLocatorError
                .resourceTemplateNotFound(name: "\(resourceName).stencil", plugin: plugin.name)
        }

        return resourceTemplatePath
    }

    func templatePath(
        for resourceName: String,
        path: AbsolutePath
    ) -> AbsolutePath? {
        guard let rootDirectory = rootDirectoryLocator.locate(from: path) else { return nil }
        let templatePath = rootDirectory
            .appending(
                components: Constants.tuistDirectoryName,
                Constants.resourceSynthesizersDirectoryName,
                "\(resourceName).stencil"
            )
        return FileHandler.shared.exists(templatePath) ? templatePath : nil
    }
}
