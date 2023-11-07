import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import XCTest
@testable import TuistKit

/// Build projects using Tuist build
final class BuildAcceptanceTestWithTemplates: TuistAcceptanceTestCase {
    func test() async throws {
        try run(InitCommand.self, "--platform", "ios", "--name", "MyApp")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await run(BuildCommand.self, "MyApp")
        try await run(BuildCommand.self, "MyApp", "--configuration", "Debug")
    }
}

final class BuildAcceptanceTestAppWithFrameworkAndTests: TuistAcceptanceTestCase {
    func test() async throws {
        try setUpFixture("app_with_framework_and_tests")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await run(BuildCommand.self, "App")
        try await run(BuildCommand.self, "AppCustomScheme")
        try await run(BuildCommand.self, "App-Workspace")
    }
}

// TODO: Fix -> This currently doesn't build because of a misconfig in Github actions where the tvOS platform is not available
// final class BuildAcceptanceTestAppWithTests: TuistAcceptanceTestCase {
//    func test() async throws {
//        try setUpFixture("app_with_tests")
//        try await run(GenerateCommand.self)
//        try await run(BuildCommand.self)
//        try await run(BuildCommand.self, "App")
//        try await run(BuildCommand.self, "App-Workspace-iOS")
//        try await run(BuildCommand.self, "App-Workspace-macOS")
//        try await run(BuildCommand.self, "App-Workspace-tvOS")
//    }
// }

final class BuildAcceptanceTestiOSAppWithCustomConfigurationAndBuildToCustomDirectory: TuistAcceptanceTestCase {
    func test() async throws {
        try setUpFixture("ios_app_with_custom_configuration")
        try await run(GenerateCommand.self)
        try await run(
            BuildCommand.self,
            "App",
            "--configuration",
            "debug",
            "--build-output-path",
            FileHandler.shared.currentPath.appending(component: "Builds").pathString
        )
        let debugPath = FileHandler.shared.currentPath.appending(
            try RelativePath(validating: "Builds/debug-iphonesimulator")
        )
        try XCTAssertDirectoryContentEqual(debugPath, ["App.app", "App.swiftmodule", "FrameworkA.framework"])
        try await run(
            BuildCommand.self,
            "App",
            "--configuration",
            "release",
            "--build-output-path",
            FileHandler.shared.currentPath.appending(component: "Builds").pathString
        )
        try XCTAssertDirectoryContentEqual(debugPath, ["App.app", "App.swiftmodule", "FrameworkA.framework"])
        let releasePath = FileHandler.shared.currentPath.appending(
            try RelativePath(validating: "Builds/release-iphonesimulator")
        )
        try XCTAssertDirectoryContentEqual(
            releasePath,
            [
                "App.app",
                "App.app.dSYM",
                "App.swiftmodule",
                "FrameworkA.framework",
                "FrameworkA.framework.dSYM",
            ]
        )
    }
}

// TODO: Enable this test and rewrite to Swift when we drop support for Xcode 14
// Scenario: The project is a framework with a Swift Macro integrated through the standard method (framework_with_swift_macro)
//   Given that tuist is available
//   And I have a working directory
//   Then I copy the fixture framework_with_swift_macro into the working directory
//   Then tuist generates the project
//   Then tuist builds the scheme Framework from the project
