import Foundation
import ServiceContextModule
import TuistAcceptanceTesting
import TuistCore
import XCTest
@testable import TuistKit

final class LintAcceptanceTests: TuistAcceptanceTestCase {
    func test_ios_app_with_headers() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithHeaders)
            try await run(InspectImplicitImportsCommand.self)
            XCTAssertStandardOutput(pattern: "We did not find any implicit dependencies in your project.")
        }
    }

    func test_ios_app_with_implicit_dependencies() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithImplicitDependencies)
            await XCTAssertThrowsSpecific(try await run(InspectImplicitImportsCommand.self), LintingError())
            XCTAssertStandardOutput(pattern: """
             - FrameworkA implicitly depends on: FrameworkB
            """)
        }
    }
}

import ServiceContextModule

final class InspectBuildAcceptanceTests: ServerAcceptanceTestCase {
    func test_xcode_project_with_inspect_build() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.xcodeProjectWithInspectBuild)
            let arguments = [
                "-scheme", "App",
                "-destination", "generic/platform=iOS Simulator",
                "-project", fixturePath.appending(component: "App.xcodeproj").pathString,
                "-resultBundlePath", fixturePath.appending(component: "result-bundle").pathString,
            ]
            try await run(XcodeBuildBuildCommand.self, arguments)
            try await run(InspectBuildCommand.self)
            let got = ServiceContext.current?.recordedUI()
            let expectedOutput = """
            ✔ Success
              Uploaded a build to the server.
            """
            XCTAssertEqual(got, expectedOutput)
        }
    }
}
