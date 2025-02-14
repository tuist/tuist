import Foundation
import ServiceContextModule
import TuistAcceptanceTesting
import TuistCore
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
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithImplicitDependencies)
            await XCTAssertThrowsSpecific(try await run(InspectImplicitImportsCommand.self), LintingError())
            XCTAssertStandardOutput(pattern: """
             - FrameworkA implicitly depends on: FrameworkB
            """)
        }
    }
}
