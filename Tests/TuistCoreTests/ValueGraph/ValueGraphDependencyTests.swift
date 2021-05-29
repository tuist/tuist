import Foundation
import TSCBasic
import TuistGraph
import XCTest
@testable import TuistCore
@testable import TuistSupportTesting

final class ValueGraphDependencyTests: TuistUnitTestCase {
    func test_isTarget() {
        XCTAssertFalse(ValueGraphDependency.testXCFramework().isTarget)
        XCTAssertFalse(ValueGraphDependency.testFramework().isTarget)
        XCTAssertFalse(ValueGraphDependency.testLibrary().isTarget)
        XCTAssertFalse(ValueGraphDependency.testPackageProduct().isTarget)
        XCTAssertTrue(ValueGraphDependency.testTarget().isTarget)
        XCTAssertFalse(ValueGraphDependency.testSDK().isTarget)
        XCTAssertFalse(ValueGraphDependency.testCocoapods().isTarget)
    }

    func test_isPrecompiled() {
        XCTAssertTrue(ValueGraphDependency.testXCFramework().isPrecompiled)
        XCTAssertTrue(ValueGraphDependency.testFramework().isPrecompiled)
        XCTAssertTrue(ValueGraphDependency.testLibrary().isPrecompiled)
        XCTAssertFalse(ValueGraphDependency.testPackageProduct().isPrecompiled)
        XCTAssertFalse(ValueGraphDependency.testTarget().isPrecompiled)
        XCTAssertFalse(ValueGraphDependency.testSDK().isPrecompiled)
        XCTAssertFalse(ValueGraphDependency.testCocoapods().isPrecompiled)
    }
}
