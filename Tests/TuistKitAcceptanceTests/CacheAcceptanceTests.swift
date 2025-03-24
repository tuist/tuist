import Foundation
import ServiceContextModule
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithFrameworks)
            try await run(CacheCommand.self, "--print-hashes")
            XCTAssertStandardOutput(pattern: """
            Framework1 - f8feceb31f42a34ebcce8b80496b4933
            Framework2-iOS - 464281b69abc95f4f2824efc01f58348
            Framework2-macOS - 2e787be6f1ac74b7db40e9cedebbac1f
            Framework3 - a4e947f548f5f16bd805719517eb7d47
            Framework4 - 5fbc3d8985c9ac2104b6100119ca61db
            Framework5 - 05a2ec5f66ed485ced57f57d6dec507a
            """)
        }
    }
}
