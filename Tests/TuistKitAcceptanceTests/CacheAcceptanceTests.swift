import Foundation
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
        try await run(CacheCommand.self, "--print-hashes")
        XCTAssertStandardOutput(pattern: """
        Framework1 - 6d268b6b438bcfdc867669241a3bcce5
        Framework2-iOS - ad3b0514c80921a12c5eb5ecc9f22494
        Framework2-macOS - 6095f4bda9c5506f41840c05ccd8d2bb
        Framework3 - 85fcd249b4baf6be8fcb77a151c9565f
        Framework4 - 4c3930dcaa86dd556ac505bb25ce7e3a
        Framework5 - 447f79879eb602cae38b1e5e51ee92aa
        """)
    }
}
