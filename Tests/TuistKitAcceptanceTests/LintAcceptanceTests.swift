import Foundation
import TuistAcceptanceTesting
import XCTest
@testable import TuistKit

final class LintAcceptanceTests: TuistAcceptanceTestCase {
    func test_ios_app_with_headers() async throws {
        try await setUpFixture(.iosAppWithHeaders)
        try await run(LintImplicitImportsCommand.self)
        XCTAssertStandardOutput(pattern: "We did not find any implicit dependencies in your project.")
    }

    func test_ios_app_with_implicit_dependencies() async throws {
        try await setUpFixture(.iosAppWithImplicitDependencies)
        do {
            try await run(LintImplicitImportsCommand.self)
        } catch let error as LintImplicitImportsServiceError {
            XCTAssertEqual(
                error.description,
                """
                Implicit dependencies were found.
                Target FrameworkA implicitly imports FrameworkB.
                """
            )
        }
    }
}
