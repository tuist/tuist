import Foundation
import TSCBasic
import TuistGraph
import TuistLoader

public final class MockConfigLoader: ConfigLoading {
    public init() {}

    public var loadConfigStub: ((AbsolutePath) throws -> Config)?
    public func loadConfig(path: AbsolutePath) throws -> Config {
        try loadConfigStub?(path) ?? .default
    }
}
