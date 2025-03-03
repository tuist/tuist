import Foundation
import Path
import TuistCore
import XcodeGraph

public final class MockFrameworkLoader: FrameworkLoading {
    public init() {}

    var loadStub: ((AbsolutePath) throws -> GraphDependency)?
    public func load(path: AbsolutePath, status: LinkingStatus) throws -> GraphDependency {
        if let loadStub {
            return try loadStub(path)
        } else {
            return GraphDependency.testFramework(path: path, status: status)
        }
    }
}
