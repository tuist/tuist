import Foundation
import ServiceContextModule
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithFrameworks)
            try await run(CacheCommand.self, "--print-hashes")
            XCTAssertStandardOutput(pattern: """
            Framework1 - c0a0ada57e1808c10604e046d299f8a9
            Framework2-iOS - 6028fd7caf391030b6884c7d57e20714
            Framework2-macOS - fd3f93f262028c340f7649500687ca53
            Framework3 - 7e8f49051fa10f156ed39a8cdad2ced9
            Framework4 - 6399e09b63b3f8502423a0145fb3ef30
            Framework5 - 27b8ad2c664f7be5b7c7e62d08efda75
            """)
        }
    }
}
