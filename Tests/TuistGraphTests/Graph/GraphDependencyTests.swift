import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class GraphDependencyTests: TuistUnitTestCase {
    func test_codable_target() {
        // Given
        let subject = GraphDependency.testTarget()

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_framework() {
        // Given
        let subject = GraphDependency.testFramework()

        // Then
        XCTAssertCodable(subject)
    }

    func test_isLinkable() {
        XCTAssertFalse(GraphDependency.testMacro().isLinkable)
        XCTAssertTrue(GraphDependency.testXCFramework().isLinkable)
        XCTAssertTrue(GraphDependency.testFramework().isLinkable)
        XCTAssertTrue(GraphDependency.testLibrary().isLinkable)
        XCTAssertFalse(GraphDependency.testBundle().isLinkable)
        XCTAssertTrue(GraphDependency.testPackageProduct().isLinkable)
        XCTAssertTrue(GraphDependency.testTarget().isLinkable)
        XCTAssertTrue(GraphDependency.testSDK().isLinkable)
    }

    func test_isPrecompiledMacro() {
        XCTAssertTrue(GraphDependency.testMacro().isPrecompiledMacro)
        XCTAssertFalse(GraphDependency.testXCFramework().isPrecompiledMacro)
        XCTAssertFalse(GraphDependency.testFramework().isPrecompiledMacro)
        XCTAssertFalse(GraphDependency.testLibrary().isPrecompiledMacro)
        XCTAssertFalse(GraphDependency.testBundle().isPrecompiledMacro)
        XCTAssertFalse(GraphDependency.testPackageProduct().isPrecompiledMacro)
        XCTAssertFalse(GraphDependency.testTarget().isPrecompiledMacro)
        XCTAssertFalse(GraphDependency.testSDK().isPrecompiledMacro)
    }
}
