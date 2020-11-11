import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistSupport
@testable import TuistSupportTesting

final class GraphDependencyReferenceTests: TuistUnitTestCase {
    func test_compare() {
        // Given
        let subject = makeReferences().sorted()

        XCTAssertEqual(subject, [
            .sdk(path: "/A.framework", status: .required, source: .developer),
            .sdk(path: "/B.framework", status: .optional, source: .developer),
            .product(target: "A", productName: "A.framework"),
            .product(target: "B", productName: "B.framework"),
            .testLibrary(path: "/libraries/A.library"),
            .testLibrary(path: "/libraries/B.library"),
            .testFramework(path: "/frameworks/A.framework"),
            .testFramework(path: "/frameworks/B.framework"),
            .testXCFramework(path: "/xcframeworks/A.xcframework"),
            .testXCFramework(path: "/xcframeworks/B.xcframework"),
            .package(product: "MyDynamicLibraryA", type: .dynamicLibrary, path: "/Packages/MyLibrary"),
            .package(product: "MyDynamicLibraryB", type: .dynamicLibrary, path: "/Packages/MyLibrary"),
            .package(product: "MyDynamicLibraryA", type: .dynamicLibrary, path: "/Packages/MyOtherLibrary"),
            .package(product: "MyDynamicLibraryB", type: .dynamicLibrary, path: "/Packages/MyOtherLibrary"),
            .package(product: "MyLibraryA", type: .staticLibrary, path: "/Packages/MyLibrary"),
            .package(product: "MyLibraryB", type: .staticLibrary, path: "/Packages/MyLibrary"),
        ])
    }

    func test_compare_isStable() {
        // Given
        let subject = makeReferences()

        // When
        let sorted = (0 ..< 10).map { _ in subject.shuffled().sorted() }

        // Then
        let unstable = sorted.dropFirst().filter { $0 != sorted.first }
        XCTAssertTrue(unstable.isEmpty)
    }

    private func makeReferences() -> [GraphDependencyReference] {
        [
            .testXCFramework(path: "/xcframeworks/A.xcframework"),
            .testXCFramework(path: "/xcframeworks/B.xcframework"),
            .testFramework(path: "/frameworks/A.framework"),
            .testFramework(path: "/frameworks/B.framework"),
            .testLibrary(path: "/libraries/A.library"),
            .testLibrary(path: "/libraries/B.library"),
            .product(target: "A", productName: "A.framework"),
            .product(target: "B", productName: "B.framework"),
            .sdk(path: "/A.framework", status: .required, source: .developer),
            .sdk(path: "/B.framework", status: .optional, source: .developer),
            .package(product: "MyLibraryA", type: .staticLibrary, path: "/Packages/MyLibrary"),
            .package(product: "MyLibraryB", type: .staticLibrary, path: "/Packages/MyLibrary"),
            .package(product: "MyDynamicLibraryA", type: .dynamicLibrary, path: "/Packages/MyLibrary"),
            .package(product: "MyDynamicLibraryB", type: .dynamicLibrary, path: "/Packages/MyLibrary"),
            .package(product: "MyDynamicLibraryA", type: .dynamicLibrary, path: "/Packages/MyOtherLibrary"),
            .package(product: "MyDynamicLibraryB", type: .dynamicLibrary, path: "/Packages/MyOtherLibrary"),
        ]
    }
}
