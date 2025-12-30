import FileSystem
import Foundation
import Path
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport

public protocol StencilPathLocating {
    func locate(at: AbsolutePath) async throws -> AbsolutePath?

    func templatePath(
        for pluginName: String,
        resourceName: String,
        stencilPlugins: [PluginStencil]
    ) async throws -> AbsolutePath

    func templatePath(
        for resourceName: String,
        path: AbsolutePath
    ) async throws -> AbsolutePath?
}

enum StencilPathLocatorError: FatalError, Equatable {
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

public final class StencilPathLocator: StencilPathLocating {
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileSystem: FileSysteming

    public init(
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileSystem = fileSystem
    }

    public func templatePath(
        for pluginName: String,
        resourceName: String,
        stencilPlugins: [PluginStencil]
    ) async throws -> AbsolutePath {
        guard let plugin = stencilPlugins.first(where: { $0.name == pluginName })
        else { throw StencilPathLocatorError.pluginNotFound(pluginName, stencilPlugins.map(\.name)) }

        let resourceTemplatePath = plugin.path
            .appending(components: "\(resourceName).stencil")
        guard try await fileSystem.exists(resourceTemplatePath)
        else {
            throw StencilPathLocatorError
                .resourceTemplateNotFound(name: "\(resourceName).stencil", plugin: plugin.name)
        }

        return resourceTemplatePath
    }

    public func templatePath(
        for resourceName: String,
        path: AbsolutePath
    ) async throws -> AbsolutePath? {
        guard let rootDirectory = try await rootDirectoryLocator.locate(from: path) else { return nil }
        let templatePath = rootDirectory
            .appending(
                components: Constants.tuistDirectoryName,
                Constants.stencilsDirectoryName,
                "\(resourceName).stencil"
            )
        return try await fileSystem.exists(templatePath) ? templatePath : nil
    }

    // MARK: - Helpers

    public func locate(at: AbsolutePath) async throws -> AbsolutePath? {
        guard let rootDirectory = try await rootDirectoryLocator.locate(from: at) else { return nil }
        let helpersDirectory = rootDirectory
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.stencilsDirectoryName)
        if try await !fileSystem.exists(helpersDirectory) { return nil }
        return helpersDirectory
    }
}
