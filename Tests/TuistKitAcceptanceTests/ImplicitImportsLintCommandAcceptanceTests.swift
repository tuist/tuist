import Foundation
import TuistAcceptanceTesting

final class ImplicitImportsLintCommandAcceptanceTests: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await setUpFixture(.iosAppWithHeaders)
        try await run(ImplicitImportsLintCommand.self)
        XCTAssertStandardOutput(pattern: "Implicit dependencies were not found.")
    }
}
