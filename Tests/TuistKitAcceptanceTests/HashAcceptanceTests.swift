import Foundation
import ServiceContextModule
import TuistAcceptanceTesting
import XCTest

final class HashAcceptanceTestXcodeProjectiOSFramework: TuistAcceptanceTestCase {
    func test_xcode_project_ios_framework() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.custom("xcode_project_ios_framework"))
            try await run(HashCommand.self)
            XCTAssertStandardOutput(
                pattern: """
                Framework - f4c285a58fdb882b527c6d5884ef52ed
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
