import Foundation
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
        try await run(CacheCommand.self, "--print-hashes")
        XCTAssertStandardOutput(pattern: """
        Framework1 - 0f2c49475bb14354dc625bd72fa7c98d
        Framework2-iOS - aca6c7f05052db078890952bfc66a9da
        Framework2-macOS - 91dbbb8ff59075cf6bdfae3e457e5edc
        Framework3 - 69b9571d2f28b09136160b15d3d5ad94
        Framework4 - 9f8a6fbe6785a9d9cb1a0d9181e7bf14
        Framework5 - 1d764f2e0bc3a6e51c4cd01a1ad9e8fb
        """)
    }
}
