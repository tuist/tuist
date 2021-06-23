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
                "A": [.xcframework(path: .current)],
            ]
        )
        let other = DependenciesGraph.test(
            externalDependencies: [
                "B": [.xcframework(path: .current)],
            ]
        )

        // Then
        XCTAssertEqual(
            try subject.merging(with: other),
            DependenciesGraph.test(
                externalDependencies: [
                    "A": [.xcframework(path: .current)],
                    "B": [.xcframework(path: .current)],
                ]
            )
        )
    }

    func test_merging_duplicate() throws {
        // Given
        let subject = DependenciesGraph.test(
            externalDependencies: [
                "A": [.xcframework(path: .current)],
            ]
        )
        let other = DependenciesGraph.test(
            externalDependencies: [
                "A": [.xcframework(path: .current)],
            ]
        )

        // Then
        XCTAssertThrowsSpecific(
            try subject.merging(with: other),
            DependenciesGraphError.duplicatedDependency(
                "A",
                [.xcframework(path: .current)],
                [.xcframework(path: .current)]
            )
        )
    }
}
