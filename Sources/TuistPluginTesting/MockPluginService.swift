import TuistCore
import TuistPlugin

public final class MockPluginService: PluginServicing {
    public init() {}

    public var loadPluginsStub: (TuistGeneratedProjectOptions) -> Plugins = { _ in .none }
    public func loadPlugins(using config: TuistGeneratedProjectOptions) throws -> Plugins {
        loadPluginsStub(config)
    }

    public var fetchRemotePluginsStub: ((TuistGeneratedProjectOptions) throws -> Void)?
    public func fetchRemotePlugins(using config: TuistGeneratedProjectOptions) throws {
        try fetchRemotePluginsStub?(config)
    }

    public var remotePluginPathsStub: ((TuistGeneratedProjectOptions) throws -> [RemotePluginPaths])?
    public func remotePluginPaths(using config: TuistGeneratedProjectOptions) throws -> [RemotePluginPaths] {
        try remotePluginPathsStub?(config) ?? []
    }
}
