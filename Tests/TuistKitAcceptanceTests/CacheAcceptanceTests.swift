import Foundation
import ServiceContextModule
import TuistAcceptanceTesting

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithFrameworks)
            try await run(CacheCommand.self, "--print-hashes")
            XCTAssertStandardOutput(pattern: """
            Framework1 - ec51624fa9e5dc8c7b44ade54780d5aa
            Framework2-iOS - cf1f625655179ca2e4d77b45a1786d81
            Framework2-macOS - c06920bbd3fa5c98e5fe842ea1a594bc
            Framework3 - 0b59f71849943925afe85184b48516c9
            Framework4 - fab923f000d87a6f77af0ef6879edcc5
            Framework5 - dca6e0375bf0410580e228fb15658ae2
            """)
        }
    }
}
