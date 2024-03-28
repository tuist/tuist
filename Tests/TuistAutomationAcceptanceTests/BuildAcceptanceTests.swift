import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import XCTest

/// Build projects using Tuist build
final class BuildAcceptanceTestWithTemplates: TuistAcceptanceTestCase {
    func test_with_templates() async throws {
        let context = MockContext()
        try await run(InitCommand.self, "--platform", "ios", "--name", "MyApp", context: context)
        try await run(InstallCommand.self, context: context)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, context: context)
        try await run(BuildCommand.self, "MyApp", context: context)
        try await run(BuildCommand.self, "MyApp", "--configuration", "Debug", context: context)
    }
}

final class BuildAcceptanceTestAppWithPreviews: TuistAcceptanceTestCase {
    func test_with_previews() async throws {
        let context = MockContext()
        try setUpFixture(.appWithPreviews)
        try await run(InstallCommand.self, context: context)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, context: context)
    }
}

final class BuildAcceptanceTestAppWithFrameworkAndTests: TuistAcceptanceTestCase {
    func test_with_framework_and_tests() async throws {
        let context = MockContext()
        try setUpFixture(.appWithFrameworkAndTests)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, context: context)
        try await run(BuildCommand.self, "App", context: context)
        try await run(BuildCommand.self, "AppCustomScheme", context: context)
        try await run(BuildCommand.self, "App-Workspace", context: context)
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
        let context = MockContext()
        try setUpFixture(.iosAppWithCustomConfiguration)
        try await run(GenerateCommand.self, context: context)
        try await run(
            BuildCommand.self,
            "App",
            "--configuration",
            "debug",
            "--build-output-path",
            fixturePath.appending(component: "Builds").pathString,
            context: context
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
            fixturePath.appending(component: "Builds").pathString,
            context: context
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
        let context = MockContext()
        try setUpFixture(.frameworkWithSwiftMacro)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, "Framework", context: context)
    }
}

final class BuildAcceptanceTestFrameworkWithSwiftMacroIntegratedWithXcodeProjPrimitives: TuistAcceptanceTestCase {
    func test_framework_with_swift_macro_integrated_with_xcode_proj_primitives() async throws {
        let context = MockContext()
        try setUpFixture(.frameworkWithNativeSwiftMacro)
        try await run(InstallCommand.self, context: context)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, "Framework", "--platform", "macos", context: context)
        try await run(BuildCommand.self, "Framework", "--platform", "ios", context: context)
    }
}

final class BuildAcceptanceTestMultiplatformAppWithExtensions: TuistAcceptanceTestCase {
    func test() async throws {
        let context = MockContext()
        try setUpFixture(.multiplatformAppWithExtension)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, "App", "--platform", "ios", context: context)
    }
}

final class BuildAcceptanceTestMultiplatformAppWithSDK: TuistAcceptanceTestCase {
    func test() async throws {
        let context = MockContext()
        try setUpFixture(.multiplatformAppWithSdk)
        try await run(InstallCommand.self, context: context)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, "App", "--platform", "macos", context: context)
        try await run(BuildCommand.self, "App", "--platform", "ios", context: context)
    }
}

final class BuildAcceptanceTestMultiplatformµFeatureUnitTestsWithExplicitDependencies: TuistAcceptanceTestCase {
    func test() async throws {
        let context = MockContext()
        try setUpFixture(.multiplatformµFeatureUnitTestsWithExplicitDependencies)
        try await run(InstallCommand.self, context: context)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, "ExampleApp", "--platform", "ios", context: context)
        try await run(TestCommand.self, "ModuleA", "--platform", "ios", context: context)
    }
}

final class BuildAcceptanceTestAppWithSPMDependencies: TuistAcceptanceTestCase {
    func test() async throws {
        let context = MockContext()
        try setUpFixture(.appWithSpmDependencies)
        try await run(InstallCommand.self, context: context)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, "App", "--platform", "ios", context: context)
    }
}

final class BuildAcceptanceTestMultiplatformAppWithMacrosAndEmbeddedWatchOSApp: TuistAcceptanceTestCase {
    func test() async throws {
        let context = MockContext()
        try setUpFixture(.multiplatformAppWithMacrosAndEmbeddedWatchOSApp)
        try await run(InstallCommand.self, context: context)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, "App", "--platform", "ios", context: context)
    }
}
