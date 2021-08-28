import Foundation
import TSCBasic
import TuistGraph
import XCTest
@testable import TuistCore
@testable import TuistSupportTesting

final class GraphDependencyTests: TuistUnitTestCase {
    func test_isTarget() {
        XCTAssertFalse(GraphDependency.testXCFramework().isTarget)
        XCTAssertFalse(GraphDependency.testFramework().isTarget)
        XCTAssertFalse(GraphDependency.testLibrary().isTarget)
        XCTAssertFalse(GraphDependency.testPackageProduct().isTarget)
        XCTAssertTrue(GraphDependency.testTarget().isTarget)
        XCTAssertFalse(GraphDependency.testSDK().isTarget)
    }

    func test_isPrecompiled() {
        XCTAssertTrue(GraphDependency.testXCFramework().isPrecompiled)
        XCTAssertTrue(GraphDependency.testFramework().isPrecompiled)
        XCTAssertTrue(GraphDependency.testLibrary().isPrecompiled)
        XCTAssertFalse(GraphDependency.testPackageProduct().isPrecompiled)
        XCTAssertFalse(GraphDependency.testTarget().isPrecompiled)
        XCTAssertFalse(GraphDependency.testSDK().isPrecompiled)
    }
}
