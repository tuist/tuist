import Foundation
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
        try await run(CacheCommand.self, "--print-hashes")
        XCTAssertStandardOutput(pattern: """
        Framework1 - 50b2bcb1b8b22700ca49ba724de1c5a5
        Framework2-iOS - aef2838a4963ec267e2af27071d72cf4
        Framework2-macOS - 723f7c59d7aadc1ef067a73041015745
        Framework3 - 1d186e71f96c0d710b10d879e579b992
        Framework4 - 0a7127fc247684c40d47983f26ba609e
        Framework5 - 87d7cde12833307e37cad3189e20441b
        """)
    }
}
