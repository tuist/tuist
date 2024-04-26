import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class MockXCFrameworkLoader: XCFrameworkLoading {
    public init() {}

    var loadStub: ((AbsolutePath) throws -> GraphDependency)?
    public func load(path: AbsolutePath, status: FrameworkStatus) throws -> GraphDependency {
        if let loadStub {
            return try loadStub(path)
        } else {
            return .testXCFramework(path: path, status: status)
        }
    }
}
