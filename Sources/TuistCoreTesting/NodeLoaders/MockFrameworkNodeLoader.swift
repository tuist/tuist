import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class MockFrameworkLoader: FrameworkLoading {
    public init() {}

    var loadStub: ((AbsolutePath) throws -> GraphDependency)?
    public func load(path: AbsolutePath) throws -> GraphDependency {
        if let loadStub = loadStub {
            return try loadStub(path)
        } else {
            return GraphDependency.testFramework(path: path)
        }
    }
}
