import Foundation
import ServiceContextModule
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithFrameworks)
            try await run(CacheCommand.self, "--print-hashes")
        }
    }
}
