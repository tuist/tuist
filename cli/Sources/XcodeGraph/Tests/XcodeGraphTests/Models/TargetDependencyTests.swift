import Foundation
import Path
import Testing
@testable import XcodeGraph

struct TargetDependencyTests {
    @Test func test_codable_framework() throws {
        // Given
        let subject = TargetDependency.framework(
            path: try AbsolutePath(validating: "/path/to/framework"),
            status: .required
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(TargetDependency.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_codable_project() throws {
        // Given
        let subject = TargetDependency.project(target: "target", path: try AbsolutePath(validating: "/path/to/target"))

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(TargetDependency.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_codable_library() throws {
        // Given
        let subject = TargetDependency.library(
            path: try AbsolutePath(validating: "/path/to/library"),
            publicHeaders: try AbsolutePath(validating: "/path/to/publicheaders"),
            swiftModuleMap: try AbsolutePath(validating: "/path/to/swiftModuleMap")
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(TargetDependency.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_filtering() throws {
        let expected: PlatformCondition? = .when([.macos])

        let subjects: [TargetDependency] = [
            .framework(path: try AbsolutePath(validating: "/"), status: .required, condition: expected),
            .library(
                path: try AbsolutePath(validating: "/"),
                publicHeaders: try AbsolutePath(validating: "/"),
                swiftModuleMap: try AbsolutePath(validating: "/"),
                condition: expected
            ),
            .sdk(name: "", status: .required, condition: expected),
            .package(product: "", type: .plugin, condition: expected),
            .target(name: "", condition: expected),
            .xcframework(
                path: try AbsolutePath(validating: "/"),
                expectedSignature: nil,
                status: .required,
                condition: expected
            ),
            .project(target: "", path: try AbsolutePath(validating: "/"), condition: expected),
        ]

        for subject in subjects {
            #expect(subject.condition == expected)
            #expect(subject.withCondition(.when([.catalyst])).condition == .when([.catalyst]))
        }
    }

    @Test func test_xctest_platformFilters_alwaysReturnAll() {
        let subject = TargetDependency.xctest

        #expect(subject.condition == nil)
        #expect(subject.withCondition(.when([.catalyst])).condition == nil)
    }
}
