import TuistCore
import TuistPlugin

public final class MockPluginService: PluginServicing {
    public init() {}

    public var loadPluginsStub: (Tuist) -> Plugins = { _ in .none }
    public func loadPlugins(using config: Tuist) throws -> Plugins {
        loadPluginsStub(config)
    }

    public var fetchRemotePluginsStub: ((Tuist) throws -> Void)?
    public func fetchRemotePlugins(using config: Tuist) throws {
        try fetchRemotePluginsStub?(config)
    }

    public var remotePluginPathsStub: ((Tuist) throws -> [RemotePluginPaths])?
    public func remotePluginPaths(using config: Tuist) throws -> [RemotePluginPaths] {
        try remotePluginPathsStub?(config) ?? []
    }
}
