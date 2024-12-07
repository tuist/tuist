import Foundation
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
        try await run(CacheCommand.self, "--print-hashes")
        XCTAssertStandardOutput(pattern: """
        Framework1 - 39b332c21093295281416a7beddd77e5
        Framework2-iOS - 165a7dfd3612fb5b00e94c21403efb75
        Framework2-macOS - 6b0b13c52190c558b100ff68ad16344f
        Framework3 - c7f4df07addce358f436c242daf393f1
        Framework4 - dd8f3348392c4cf4d3afff09adea6e6e
        Framework5 - 787bba0da894622ad1a7be01167f6526
        """)
    }
}
