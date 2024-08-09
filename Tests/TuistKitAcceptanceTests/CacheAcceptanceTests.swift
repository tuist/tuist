import Foundation
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
        try await run(CacheCommand.self, "--print-hashes")
        XCTAssertStandardOutput(pattern: """
        Framework1 - e845d28f46587f3fe6b4b558dd4a1b05
        Framework2-iOS - 5f1ab129436c39c03f2eed8bf6296fae
        Framework2-macOS - 643fa7eae68924aa6fbfb46daff362c8
        Framework3 - 2e484e2f796c7b3c108f00d51d24d261
        Framework4 - fcdfa208380722d426314089c4fd407f
        Framework5 - 362f186534c225e0068aa20c0b95b603
        """)
    }
}
