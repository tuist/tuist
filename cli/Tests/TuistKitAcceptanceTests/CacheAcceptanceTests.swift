import Foundation
import TuistAcceptanceTesting
import TuistTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await withMockedDependencies {
            try await setUpFixture("generated_ios_app_with_frameworks")
            try await run(CacheCommand.self, "--print-hashes")
        }
    }
}
