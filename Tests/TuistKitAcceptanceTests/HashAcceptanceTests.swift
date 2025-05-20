import Foundation
import TuistAcceptanceTesting
import XCTest
import TuistSupportTesting
@testable import TuistKit

final class HashAcceptanceTestXcodeProjectiOSFramework: TuistAcceptanceTestCase {
    func test_xcode_project_ios_framework() async throws {
        try await withTestingDependencies {
            try await setUpFixture("ios_app_with_frameworks")
            try await run(HashCacheCommand.self)
            XCTAssertStandardOutput(pattern: "Framework1 -")
            XCTAssertStandardOutput(pattern: "Framework2-iOS -")
            XCTAssertStandardOutput(pattern: "Framework2-macOS -")
            XCTAssertStandardOutput(pattern: "Framework3 -")
            XCTAssertStandardOutput(pattern: "Framework4 -")
            XCTAssertStandardOutput(pattern: "Framework5 -")
        }
    }
}
