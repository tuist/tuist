import Foundation
import Path
import TuistCore
@testable import TuistLoader

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
