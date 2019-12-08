import Basic
import Foundation
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistSupport
@testable import TuistSupportTesting

final class GraphDependencyReferenceTests: TuistUnitTestCase {
    func test_equal() {
        let subjects: [(GraphDependencyReference, GraphDependencyReference, Bool)] = [
            // Absolute
            (.absolute(.init("/a.framework")), .absolute(.init("/a.framework")), true),
            (.absolute(.init("/a.framework")), .product(target: "Main", productName: "Main.app"), false),
            (.absolute(.init("/a.framework")), .sdk(.init("/CoreData.framework"), .required), false),

            // Product
            (.product(target: "Main", productName: "Main.app"), .product(target: "Main", productName: "Main.app"), true),
            (.product(target: "Main", productName: "Main.app"), .absolute(.init("/a.framework")), false),
            (.product(target: "Main", productName: "Main.app"), .sdk(.init("/CoreData.framework"), .required), false),
            (.product(target: "Main-iOS", productName: "Main.app"), .product(target: "Main-macOS", productName: "Main.app"), false),

            // SDK
            (.sdk(.init("/CoreData.framework"), .required), .sdk(.init("/CoreData.framework"), .required), true),
            (.sdk(.init("/CoreData.framework"), .required), .product(target: "Main", productName: "Main.app"), false),
            (.sdk(.init("/CoreData.framework"), .required), .absolute(.init("/a.framework")), false),
        ]

        XCTAssertEqualPairs(subjects)
    }

    func test_compare() {
        XCTAssertFalse(GraphDependencyReference.absolute("/A") < .absolute("/A"))
        XCTAssertTrue(GraphDependencyReference.absolute("/A") < .absolute("/B"))
        XCTAssertFalse(GraphDependencyReference.absolute("/B") < .absolute("/A"))

        XCTAssertFalse(GraphDependencyReference.product(target: "A", productName: "A.framework") < .product(target: "A", productName: "A.framework"))
        XCTAssertTrue(GraphDependencyReference.product(target: "A", productName: "A.framework") < .product(target: "B", productName: "B.framework"))
        XCTAssertFalse(GraphDependencyReference.product(target: "B", productName: "B.framework") < .product(target: "A", productName: "A.framework"))
        XCTAssertTrue(GraphDependencyReference.product(target: "A", productName: "A.app") < .product(target: "A", productName: "A.framework"))

        XCTAssertTrue(GraphDependencyReference.product(target: "/A", productName: "A.framework") < .absolute("/A"))
        XCTAssertTrue(GraphDependencyReference.product(target: "/A", productName: "A.framework") < .absolute("/B"))
        XCTAssertTrue(GraphDependencyReference.product(target: "/B", productName: "B.framework") < .absolute("/A"))

        XCTAssertFalse(GraphDependencyReference.absolute("/A") < .product(target: "/A", productName: "A.framework"))
        XCTAssertFalse(GraphDependencyReference.absolute("/A") < .product(target: "/B", productName: "B.framework"))
        XCTAssertFalse(GraphDependencyReference.absolute("/B") < .product(target: "/A", productName: "A.framework"))
    }

    func test_compare_isStable() {
        // Given
        let subject: [GraphDependencyReference] = [
            .absolute("/A"),
            .absolute("/B"),
            .product(target: "A", productName: "A.framework"),
            .product(target: "B", productName: "B.framework"),
            .sdk("/A.framework", .required),
            .sdk("/B.framework", .optional),
        ]

        // When
        let sorted = (0 ..< 10).map { _ in subject.shuffled().sorted() }

        // Then
        let unstable = sorted.dropFirst().filter { $0 != sorted.first }
        XCTAssertTrue(unstable.isEmpty)
    }
}
