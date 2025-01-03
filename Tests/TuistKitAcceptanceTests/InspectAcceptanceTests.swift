import Foundation
import ServiceContextModule
import TuistAcceptanceTesting
import XCTest
@testable import TuistKit

final class LintAcceptanceTests: TuistAcceptanceTestCase {
    func test_ios_app_with_headers() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithHeaders)
            try await run(InspectImplicitImportsCommand.self)
            XCTAssertStandardOutput(pattern: "We did not find any implicit dependencies in your project.")
        }
    }

    func test_ios_app_with_implicit_dependencies() async throws {
        try await setUpFixture(.iosAppWithImplicitDependencies)
        do {
            try await run(InspectImplicitImportsCommand.self)
        } catch let error as InspectImplicitImportsServiceError {
            XCTAssertEqual(
                error.description,
                """
                The following implicit dependencies were found:
                 - FrameworkA implicitly depends on: FrameworkB
                """
            )
        }
    }
}
