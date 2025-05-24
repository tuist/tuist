import Foundation
import TuistAcceptanceTesting
import TuistCore
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class LintAcceptanceTests: TuistAcceptanceTestCase {
    func test_ios_app_with_headers() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.iosAppWithHeaders)
            try await run(InspectImplicitImportsCommand.self)
            XCTAssertStandardOutput(pattern: "We did not find any implicit dependencies in your project.")
        }
    }

    func test_ios_app_with_implicit_dependencies() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.iosAppWithImplicitDependencies)
            await XCTAssertThrowsSpecific(try await run(InspectImplicitImportsCommand.self), LintingError())
            XCTAssertStandardOutput(pattern: """
             - FrameworkA implicitly depends on: FrameworkB
            """)
        }
    }
}

final class InspectBuildAcceptanceTests: ServerAcceptanceTestCase {
    func test_xcode_project_with_inspect_build() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.xcodeProjectWithInspectBuild)
            let arguments = [
                "-scheme", "App",
                "-destination", "generic/platform=iOS Simulator",
                "-project", fixturePath.appending(component: "App.xcodeproj").pathString,
                "-resultBundlePath", fixturePath.appending(component: "result-bundle").pathString,
            ]
            try await run(XcodeBuildBuildCommand.self, arguments)
            try await run(InspectBuildCommand.self)
            XCTAssertEqual(ui(), """
            ✔ Success
              Uploaded a build to the server.
            """)
        }
    }
}

final class InspectBundleAcceptanceTests: ServerAcceptanceTestCase {
    func test_xcode_project_with_inspect_build() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.xcodeProjectWithInspectBuild)
            let arguments = [
                "-scheme", "App",
                "-destination", "generic/platform=iOS Simulator",
                "-project", fixturePath.appending(component: "App.xcodeproj").pathString,
                "-derivedDataPath", fixturePath.appending(component: "App").pathString,
            ]
            try await run(XcodeBuildBuildCommand.self, arguments)
            try await run(
                InspectBundleCommand.self,
                fixturePath.appending(components: "App", "Build", "Products", "Debug-iphonesimulator", "App.app").pathString
            )
            XCTAssertTrue(ui().contains("✔︎ Bundle analyzed") == true)
        }
    }
}
