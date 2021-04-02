import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import TuistGraph

protocol PluginsHelping {
    func templatePath(
        for pluginName: String,
        resourceName: String,
        resourceSynthesizerPlugins: [ResourceSynthesizerPlugin]
    ) throws -> AbsolutePath
}

enum PluginsHelperError: FatalError, Equatable {
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

final class PluginsHelper: PluginsHelping {
    func templatePath(
        for pluginName: String,
        resourceName: String,
        resourceSynthesizerPlugins: [ResourceSynthesizerPlugin]
    ) throws -> AbsolutePath {
        guard
            let plugin = resourceSynthesizerPlugins.first(where: { $0.name == pluginName })
        else { throw PluginsHelperError.pluginNotFound(pluginName, resourceSynthesizerPlugins.map(\.name)) }
        
        let resourceTemplatePath = plugin.path
            .appending(components: "\(resourceName).stencil")
        guard
            FileHandler.shared.exists(resourceTemplatePath)
        else { throw PluginsHelperError.resourceTemplateNotFound(name: "\(resourceName).stencil", plugin: plugin.name) }
        
        return resourceTemplatePath
    }
}
