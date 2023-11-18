import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class TargetDependencyTests: TuistUnitTestCase {
    func test_codable_framework() {
        // Given
        let subject = TargetDependency.framework(
            path: "/path/to/framework",
            status: .required
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_project() {
        // Given
        let subject = TargetDependency.project(target: "target", path: "/path/to/target")

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_library() {
        // Given
        let subject = TargetDependency.library(
            path: "/path/to/library",
            publicHeaders: "/path/to/publicheaders",
            swiftModuleMap: "/path/to/swiftModuleMap"
        )

        // Then
        XCTAssertCodable(subject)
    }
    
    func test_filtering() {
        let expected: PlatformFilters = [.macos]
        
        let subjects: [TargetDependency] = [
            .framework(path: "/", status: .required, platformFilters: expected),
            .library(path: "/", publicHeaders: "/", swiftModuleMap: "/", platformFilters: expected),
            .sdk(name: "", status: .required, platformFilters: expected),
            .package(product: "", type: .plugin, platformFilters: expected),
            .target(name: "", platformFilters: expected),
            .xcframework(path: "/", status: .required, platformFilters: expected),
            .project(target: "", path: "/", platformFilters: expected)
        ]
        
        for subject in subjects {
            XCTAssertEqual(subject.platformFilters, expected)
            XCTAssertEqual(subject.withFilters([.catalyst]).platformFilters, Set([.catalyst]))
        }  
    }

    func test_xctest_platformFilters_alwaysReturnAll() {
        let subject = TargetDependency.xctest

        XCTAssertEqual(subject.platformFilters, .all)
        XCTAssertEqual(subject.withFilters([.catalyst]).platformFilters, PlatformFilters.all)
    }
}
