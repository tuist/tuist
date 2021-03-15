import TuistGraph
import TuistPlugin

public final class MockPluginService: PluginServicing {
    public init() {}

    public var loadPluginsStub: (Config) -> Plugins = { _ in .none }
    public func loadPlugins(using config: Config) throws -> Plugins {
        loadPluginsStub(config)
    }
}
