import Foundation
import Mockable
import Path
import TuistCore
import XcodeGraph
import XCTest
@testable import TuistGenerator

final class FrameworkSearchPathConsolidationTests: XCTestCase {
    func test_compute_consolidates_whenManyPrecompiledPaths() throws {
        // Given
        var dependencies: [GraphDependencyReference] = []
        for i in 0 ..< 25 {
            dependencies.append(
                GraphDependencyReference.testXCFramework(
                    path: try AbsolutePath(validating: "/path/cache/hash\(i)/Module\(i).xcframework")
                )
            )
        }
        dependencies.append(
            GraphDependencyReference.testSDK(path: "/XCTest.framework", source: .developer)
        )
        let graphTraverser = MockGraphTraversing()
        given(graphTraverser)
            .searchablePathDependencies(path: .any, name: .any)
            .willReturn(Set(dependencies))

        // When
        let consolidation = try FrameworkSearchPathConsolidation.compute(
            targetName: "MyTarget",
            projectPath: try AbsolutePath(validating: "/path"),
            sourceRootPath: try AbsolutePath(validating: "/path"),
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertTrue(consolidation.isConsolidated)
        XCTAssertTrue(
            consolidation.responseFilePath.pathString.hasSuffix("Derived/FrameworkSearchPaths/MyTarget.resp")
        )
        for i in 0 ..< 25 {
            XCTAssertTrue(
                consolidation.responseFileContents.contains("-F/path/cache/hash\(i)"),
                "Response file contents should contain -F flag for hash\(i)"
            )
        }
    }

    func test_compute_doesNotConsolidate_whenFewPrecompiledPaths() throws {
        // Given
        let dependencies: [GraphDependencyReference] = [
            .testXCFramework(path: try AbsolutePath(validating: "/path/cache/hash0/Module0.xcframework")),
        ]
        let graphTraverser = MockGraphTraversing()
        given(graphTraverser)
            .searchablePathDependencies(path: .any, name: .any)
            .willReturn(Set(dependencies))

        // When
        let consolidation = try FrameworkSearchPathConsolidation.compute(
            targetName: "MyTarget",
            projectPath: try AbsolutePath(validating: "/path"),
            sourceRootPath: try AbsolutePath(validating: "/path"),
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertFalse(consolidation.isConsolidated)
    }
}
