import Foundation
import Path
import TuistCore
import XcodeGraph

public final class MockXCFrameworkLoader: XCFrameworkLoading {
    public init() {}

    var loadStub: ((AbsolutePath) throws -> GraphDependency)?
    public func load(
        path: Path.AbsolutePath,
        expectedSignature _: XcodeGraph.XCFrameworkSignature?,
        status: XcodeGraph.LinkingStatus
    ) throws -> GraphDependency {
        if let loadStub {
            return try loadStub(path)
        } else {
            return .testXCFramework(path: path, status: status)
        }
    }
}
