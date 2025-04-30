import Foundation
import ServiceContextModule
import TuistAcceptanceTesting
import XCTest
@testable import TuistKit

final class HashAcceptanceTestXcodeProjectiOSFramework: TuistAcceptanceTestCase {
    func test_xcode_project_ios_framework() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture("xcode_project_ios_framework")
            try await run(HashCommand.self)
            XCTAssertStandardOutput(
                pattern: """
                Framework -
                """
            )
        }
    }
}

final class HashAcceptanceTestXcodeProjectiOSApp: TuistAcceptanceTestCase {
    func test_xcode_project_ios_app() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.custom("xcode_project_ios_app"))
            try await run(HashCommand.self)
            XCTAssertEqual(
                ServiceContext.current?.recordedUI()
                    .contains("The project contains no hasheable targets."), true
            )
        }
    }
}
