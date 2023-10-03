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

    func test_isStaticPrecompiled() {
        XCTAssertTrue(GraphDependency.testXCFramework(linking: .static).isStaticPrecompiled)
        XCTAssertTrue(GraphDependency.testFramework(linking: .static).isStaticPrecompiled)
        XCTAssertTrue(GraphDependency.testLibrary(linking: .static).isStaticPrecompiled)
        XCTAssertFalse(GraphDependency.testPackageProduct().isStaticPrecompiled)
        XCTAssertFalse(GraphDependency.testTarget().isStaticPrecompiled)
        XCTAssertFalse(GraphDependency.testSDK().isStaticPrecompiled)
    }

    func test_isDynamicPrecompiled() {
        XCTAssertTrue(GraphDependency.testXCFramework(linking: .dynamic).isDynamicPrecompiled)
        XCTAssertTrue(GraphDependency.testFramework(linking: .dynamic).isDynamicPrecompiled)
        XCTAssertTrue(GraphDependency.testLibrary(linking: .dynamic).isDynamicPrecompiled)
        XCTAssertFalse(GraphDependency.testPackageProduct().isDynamicPrecompiled)
        XCTAssertFalse(GraphDependency.testTarget().isDynamicPrecompiled)
        XCTAssertFalse(GraphDependency.testSDK().isDynamicPrecompiled)
    }
}
