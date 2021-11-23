import TuistGraph
import TuistPlugin

public final class MockPluginService: PluginServicing {
    public init() {}

    public var loadPluginsStub: (Config) -> Plugins = { _ in .none }
    public func loadPlugins(using config: Config) throws -> Plugins {
        loadPluginsStub(config)
    }

    public var fetchRemotePluginsStub: ((Config) throws -> Void)?
    public func fetchRemotePlugins(using config: Config) throws {
        try fetchRemotePluginsStub?(config)
    }

    public var remotePluginPathsStub: ((Config) throws -> [RemotePluginPaths])?
    public func remotePluginPaths(using config: Config) throws -> [RemotePluginPaths] {
        try remotePluginPathsStub?(config) ?? []
    }
}
