import Foundation
import TuistSupport
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class DependenciesGraphTests: TuistUnitTestCase {
    func test_codable_xcframework() {
        // Given
        let subject = DependenciesGraph.test()

        // Then
        XCTAssertCodable(subject)
    }

    func test_merging() throws {
        // Given
        let subject = DependenciesGraph.test(
            externalDependencies: [
                "A": .xcframework(name: "A", path: .current, architectures: []),
            ]
        )
        let other = DependenciesGraph.test(
            externalDependencies: [
                "B": .xcframework(name: "B", path: .current, architectures: []),
            ]
        )

        // Then
        XCTAssertEqual(
            try subject.merging(with: other),
            DependenciesGraph.test(
                externalDependencies: [
                    "A": .xcframework(name: "A", path: .current, architectures: []),
                    "B": .xcframework(name: "B", path: .current, architectures: []),
                ]
            )
        )
    }

    func test_merging_duplicate() throws {
        // Given
        let subject = DependenciesGraph.test(
            externalDependencies: [
                "A": .xcframework(name: "A", path: .current, architectures: []),
            ]
        )
        let other = DependenciesGraph.test(
            externalDependencies: [
                "A": .xcframework(name: "A", path: .current, architectures: []),
            ]
        )

        // Then
        XCTAssertThrowsSpecific(
            try subject.merging(with: other),
            DependenciesGraphError.duplicatedDependency(
                "A",
                .xcframework(name: "A", path: .current, architectures: []),
                .xcframework(name: "A", path: .current, architectures: [])
            )
        )
    }
}
