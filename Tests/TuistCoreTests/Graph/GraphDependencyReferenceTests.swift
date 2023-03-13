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
        let subject: [GraphDependencyReference] = [
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
            .bundle(path: "/A.bundle"),
            .bundle(path: "/B.bundle"),
        ]

        // When
        let results = subject.shuffled().sorted()

        XCTAssertEqual(results, [
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
            .bundle(path: "/A.bundle"),
            .bundle(path: "/B.bundle"),
        ])
    }

    func test_compare_isStable() {
        // Given
        let sampleNames = [
            "A",
            "B",
            "C",
            "Core",
            "MyService",
            "MyUI",
        ]
        let subject = KnownGraphDependencyReference.allCases.flatMap { knownType in
            sampleNames.flatMap(knownType.sampleReferences)
        }

        // When
        let sorted = (0 ..< 10).map { _ in subject.shuffled().sorted() }

        // Then
        let unstable = sorted.dropFirst().filter { $0 != sorted.first }
        XCTAssertTrue(unstable.isEmpty)
    }
}

/// A helper type to generate samples of `GraphDependencyReference`
/// This needs to be kept in sync with the types offered there.
private enum KnownGraphDependencyReference: CaseIterable {
    case xcframework
    case framework
    case bundle
    case library
    case product
    case sdk

    func sampleReferences(name: String) -> [GraphDependencyReference] {
        switch self {
        case .xcframework:
            return [.testXCFramework(path: try! AbsolutePath(validating: "/dependencies/\(name).xcframework"))]
        case .framework:
            return [.testFramework(path: try! AbsolutePath(validating: "/dependencies/\(name).framework"))]
        case .bundle:
            return [.bundle(path: try! AbsolutePath(validating: "/dependencies/\(name).bundle"))]
        case .library:
            return [.testLibrary(path: try! AbsolutePath(validating: "/dependencies/lib\(name).a"))]
        case .product:
            return [
                .product(target: name, productName: "\(name).framework", platformFilter: nil),
                .product(target: name, productName: "\(name).framework", platformFilter: .ios),
                .product(target: name, productName: "\(name).framework", platformFilter: .catalyst),
                .product(target: name, productName: "lib\(name).a", platformFilter: nil),
                .product(target: name, productName: "lib\(name).a", platformFilter: .ios),
                .product(target: name, productName: "lib\(name).a", platformFilter: .catalyst),
            ]
        case .sdk:
            return [
                .sdk(path: try! AbsolutePath(validating: "/sdks/\(name).framework"), status: .required, source: .system),
                .sdk(path: try! AbsolutePath(validating: "/sdks/\(name).tbd"), status: .required, source: .system),
            ]
        }
    }
}

extension GraphDependencyReference {
    // This is added to enforce keeping `KnownGraphDependencyReference` and `GraphDependencyReference` in sync
    private var correspondingKnownType: KnownGraphDependencyReference {
        switch self {
        case .xcframework:
            return .xcframework
        case .framework:
            return .framework
        case .bundle:
            return .bundle
        case .library:
            return .library
        case .product:
            return .product
        case .sdk:
            return .sdk
        }
    }
}
