import Foundation
import Testing
import TuistTesting
@testable import ProjectDescription

struct TargetDependencyTests {
    @Test func toJSON_when_target() throws {
        let subject = TargetDependency.target(name: "Target")
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func toJSON_when_project() throws {
        let subject = TargetDependency.project(target: "target", path: "path")
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func toJSON_when_framework() throws {
        let subject = TargetDependency.framework(path: "/path/framework.framework")
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func toJSON_when_library() throws {
        let subject = TargetDependency.library(
            path: "/path/library.a",
            publicHeaders: "/path/headers",
            swiftModuleMap: "/path/modulemap"
        )
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func sdk_codable() throws {
        // Given
        let sdks: [TargetDependency] = [
            .sdk(name: "A", type: .framework),
            .sdk(name: "B", type: .framework, status: .required),
            .sdk(name: "c", type: .framework, status: .optional),
        ]

        // When
        let encoded = try JSONEncoder().encode(sdks)
        let decoded = try JSONDecoder().decode([TargetDependency].self, from: encoded)

        // Then
        #expect(decoded == sdks)
    }

    @Test func xcframework_codable() throws {
        // Given
        let subject: [TargetDependency] = [
            .xcframework(path: "/path/framework.xcframework"),
        ]

        // Then
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func instanceTarget() {
        let target: Target = .target(name: "Target", destinations: .iOS, product: .framework, bundleId: "bundleId")
        let subject = TargetDependency.target(target)
        #expect(subject == TargetDependency.target(name: "Target"))
    }
}
