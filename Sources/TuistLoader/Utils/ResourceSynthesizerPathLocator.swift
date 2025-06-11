import FileSystem
import Foundation
import Path
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport

public protocol ResourceSynthesizerPathLocating {
    func locate(at: AbsolutePath) async throws -> AbsolutePath?

    func templatePath(
        for pluginName: String,
        resourceName: String,
        resourceSynthesizerPlugins: [TuistCore.PluginResourceSynthesizer]
    ) async throws -> AbsolutePath

    func templatePath(
        for resourceName: String,
        path: AbsolutePath
    ) async throws -> AbsolutePath?
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

public final class ResourceSynthesizerPathLocator: ResourceSynthesizerPathLocating {
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
        resourceSynthesizerPlugins: [PluginResourceSynthesizer]
    ) async throws -> AbsolutePath {
        guard let plugin = resourceSynthesizerPlugins.first(where: { $0.name == pluginName })
        else { throw ResourceSynthesizerPathLocatorError.pluginNotFound(pluginName, resourceSynthesizerPlugins.map(\.name)) }

        let resourceTemplatePath = plugin.path
            .appending(components: "\(resourceName).stencil")
        guard try await fileSystem.exists(resourceTemplatePath)
        else {
            throw ResourceSynthesizerPathLocatorError
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
                Constants.resourceSynthesizersDirectoryName,
                "\(resourceName).stencil"
            )
        return try await fileSystem.exists(templatePath) ? templatePath : nil
    }

    // MARK: - Helpers

    public func locate(at: AbsolutePath) async throws -> AbsolutePath? {
        guard let rootDirectory = try await rootDirectoryLocator.locate(from: at) else { return nil }
        let helpersDirectory = rootDirectory
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.resourceSynthesizersDirectoryName)
        if try await !fileSystem.exists(helpersDirectory) { return nil }
        return helpersDirectory
    }
}

#if DEBUG
    public final class MockResourceSynthesizerPathLocator: ResourceSynthesizerPathLocating {
        public init() {}

        public var templatePathStub: ((String, String, [PluginResourceSynthesizer]) throws -> AbsolutePath)?
        public func templatePath(
            for pluginName: String,
            resourceName: String,
            resourceSynthesizerPlugins: [PluginResourceSynthesizer]
        ) throws -> AbsolutePath {
            try templatePathStub?(pluginName, resourceName, resourceSynthesizerPlugins) ?? AbsolutePath(validating: "/test")
        }

        public var templatePathResourceStub: ((String, AbsolutePath) -> AbsolutePath?)?
        public func templatePath(
            for resourceName: String,
            path: AbsolutePath
        ) -> AbsolutePath? {
            templatePathResourceStub?(resourceName, path)
        }

        public var locateStub: ((AbsolutePath) -> AbsolutePath?)?
        public func locate(at: Path.AbsolutePath) -> Path.AbsolutePath? {
            locateStub?(at)
        }
    }
#endif
