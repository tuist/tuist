import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import XCTest

/// Build projects using Tuist build
final class BuildAcceptanceTestWithTemplates: TuistAcceptanceTestCase {
    func test_with_templates() async throws {
        try run(InitCommand.self, "--platform", "ios", "--name", "MyApp")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await run(BuildCommand.self, "MyApp")
        try await run(BuildCommand.self, "MyApp", "--configuration", "Debug")
    }
}

final class BuildAcceptanceTestAppWithFrameworkAndTests: TuistAcceptanceTestCase {
    func test_with_framework_and_tests() async throws {
        try setUpFixture(.appWithFrameworkAndTest)
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
    func test_ios_app_with_custom_and_build_to_custom_directory() async throws {
        try setUpFixture(.iosAppWithCustomConfiguration)
        try await run(GenerateCommand.self)
        try await run(
            BuildCommand.self,
            "App",
            "--configuration",
            "debug",
            "--build-output-path",
            fixturePath.appending(component: "Builds").pathString
        )
        let debugPath = fixturePath.appending(
            try RelativePath(validating: "Builds/debug-iphonesimulator")
        )
        try XCTAssertDirectoryContentEqual(debugPath, ["App.app", "App.swiftmodule", "FrameworkA.framework"])
        try await run(
            BuildCommand.self,
            "App",
            "--configuration",
            "release",
            "--build-output-path",
            fixturePath.appending(component: "Builds").pathString
        )
        try XCTAssertDirectoryContentEqual(debugPath, ["App.app", "App.swiftmodule", "FrameworkA.framework"])
        let releasePath = fixturePath.appending(
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

final class BuildAcceptanceTestFrameworkWithSwiftMacroIntegratedWithStandardMethod: TuistAcceptanceTestCase {
    func test_framework_with_swift_macro_integrated_with_standard_method() async throws {
        try setUpFixture(.frameworkWithSwiftMacro)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "Framework")
    }
}

final class BuildAcceptanceTestFrameworkWithSwiftMacroIntegratedWithXcodeProjPrimitives: TuistAcceptanceTestCase {
    func test_framework_with_swift_macro_integrated_with_xcode_proj_primitives() async throws {
        try setUpFixture(.frameworkWithNativeSwiftMacro)
        try await run(FetchCommand.self)
        try await run(BuildCommand.self, "Framework", "--platform", "macos")
        try await run(BuildCommand.self, "Framework", "--platform", "ios")
    }
}

final class BuildAcceptanceTestMultiplatformAppWithExtensions: TuistAcceptanceTestCase {
    func test() async throws {
        try setUpFixture(.multiplatformAppWithExtensions)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "ios")
    }
}

final class BuildAcceptanceTestMultiplatformAppWithSDK: TuistAcceptanceTestCase {
    func test() async throws {
        try setUpFixture(.multiplatformAppWithSdk)
        try await run(FetchCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "macos")
        try await run(BuildCommand.self, "App", "--platform", "ios")
    }
}

final class BuildAcceptanceTestAppWithSPMDependencies: TuistAcceptanceTestCase {
    func test() async throws {
        try setUpFixture(.appWithSpmDependencies)
        try await run(FetchCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "ios")
    }
}
