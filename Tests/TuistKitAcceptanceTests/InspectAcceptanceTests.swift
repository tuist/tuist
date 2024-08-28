import Foundation
import TuistAcceptanceTesting
import XCTest
@testable import TuistKit

final class InspectAcceptanceTests: TuistAcceptanceTestCase {
    func test_ios_app_with_headers() async throws {
        try await setUpFixture(.iosAppWithHeaders)
        try await run(InspectImplicitImportsCommand.self)
        XCTAssertStandardOutput(pattern: "We did not find any implicit dependencies in your project.")
    }

    func test_ios_app_with_implicit_dependencies() async throws {
        try await setUpFixture(.iosAppWithImplicitDependencies)
        try await run(InspectImplicitImportsCommand.self)
        XCTAssertStandardOutput(
            pattern:
            """
            The following implicit dependencies were found:
            Target FrameworkA implicitly imports FrameworkB.
            """
        )
    }

    func test_ios_app_with_implicit_dependencies_strict() async throws {
        try await setUpFixture(.iosAppWithImplicitDependencies)
        do {
            try await run(InspectImplicitImportsCommand.self)
        } catch let error as InspectImplicitImportsServiceError {
            XCTAssertEqual(
                error.description,
                """
                The following implicit dependencies were found:
                Target FrameworkA implicitly imports FrameworkB.
                """
            )
        }
    }

    func test_ios_app_with_implicit_dependencies_xcode() async throws {
        try await setUpFixture(.iosAppWithImplicitDependencies)
        try await run(InspectImplicitImportsCommand.self, ["--xcode"])

        XCTAssertStandardOutput(
            pattern: "The following implicit dependencies were found:"
        )
        XCTAssertStandardOutput(
            pattern: "ios_app_with_implicit_dependencies/Targets/FrameworkA/Sources/FrameworkA.swift:2: warning: Target FrameworkB was implicitly imported"
        )
    }
}
