import Foundation
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
        try await run(CacheCommand.self, "--print-hashes")
        XCTAssertStandardOutput(pattern: """
        Framework1 - 23fb81f8d50af4689276b503767b3301
        Framework2-iOS - 4ec5d3b1a6a2a40ea3be26b71c4e0cdc
        Framework2-macOS - 91dbbb8ff59075cf6bdfae3e457e5edc
        Framework3 - 8bf347d920ed3d639b946adb57897ee4
        Framework4 - f9cc1e43001b492f158e1ca9a2b37470
        Framework5 - 91c354b8eee20ef01e01020a1f56d215
        """)
    }
}
