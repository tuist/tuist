import Foundation
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
        try await run(CacheCommand.self, "--print-hashes")
        XCTAssertStandardOutput(pattern: """
        Framework1 - 31b5dd46503cc78a7d84514b3a59e462
        Framework2-iOS - 75676dc68658f4996630a6eb070f3072
        Framework2-macOS - 965232ae7d0ef41aa39a5556dae4dc50
        Framework3 - 8e0d6b1a1fc70c0b9f27c41e1b0669d5
        Framework4 - 3657f4ec388cc692d6f18ed906838d71
        Framework5 - daf3deb97fcd2aef89d7f417bdccac0b
        """)
    }
}
