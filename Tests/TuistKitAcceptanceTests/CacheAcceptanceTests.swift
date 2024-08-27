import Foundation
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
        try await run(CacheCommand.self, "--print-hashes")
        XCTAssertStandardOutput(pattern: """
        Framework1 - 663553b66e63092f75dd7493d61d4b0c
        Framework2-iOS - 434fe77143dd5fc022e13f3342d7cbb9
        Framework2-macOS - 1b2c1e8437d59b21f5826954dd832b08
        Framework3 - 1aa1061078d69e5f1dfad69517f899b0
        Framework4 - f839bd406fb2b59d35679765f3a97e88
        Framework5 - 2f5efe485dd028c76986eb5e62a9628a
        """)
    }
}
