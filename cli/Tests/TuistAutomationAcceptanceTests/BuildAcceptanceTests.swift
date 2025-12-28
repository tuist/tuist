import FileSystem
import Path
import Testing
import TuistAcceptanceTesting
import TuistSupport
import TuistTesting
import XCTest
@testable import TuistKit

struct BuildAcceptanceTests {
    @Test(
        .withFixture("generated_multiplatform_app_with_extension"),
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func multiplatform_app_with_extension() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When/Then
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        try await TuistTest.run(
            BuildCommand.self,
            [
                "App",
                "--path",
                fixtureDirectory.pathString,
                "--platform",
                "ios",
                "--derived-data-path",
                temporaryDirectory.pathString,
            ]
        )
    }

    @Test(
        .withFixture("generated_ios_app_with_framework_buildable_folders_and_xcassets"),
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func ios_app_with_framework_buildable_folders_and_xcassets() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When/Then
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        try await TuistTest.run(
            BuildCommand.self,
            [
                "App",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
            ]
        )
    }

    @Test(
        .withFixture("generated_app_with_buildable_folders"),
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func app_with_buildable_folders() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When/Then
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        try await TuistTest.run(
            BuildCommand.self,
            [
                "App",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
            ]
        )
    }
}

/// Build projects using Tuist build
final class BuildAcceptanceTestWithTemplates: TuistAcceptanceTestCase {
    func test_with_templates() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                let initAnswers = InitPromptAnswers(
                    workflowType: .createGeneratedProject,
                    integrateWithServer: false,
                    generatedProjectPlatform: "ios",
                    generatedProjectName: "MyApp",
                    accountType: .createOrganizationAccount,
                    newOrganizationAccountHandle: "organization"
                )
                try await run(
                    InitCommand.self,
                    "--answers",
                    initAnswers.base64EncodedJSONString(),
                    "--path",
                    temporaryDirectory.pathString
                )
                self.fixturePath = temporaryDirectory.appending(component: "MyApp")
                try await run(InstallCommand.self)
                try await run(GenerateCommand.self)
                try await run(BuildCommand.self)
                try await run(BuildCommand.self, "MyApp")
                try await run(BuildCommand.self, "MyApp", "--configuration", "Debug")
                try await run(BuildCommand.self, "MyApp", "--", "-parallelizeTargets", "-enableAddressSanitizer", "YES")
            }
        }
    }
}

final class BuildAcceptanceTestInvalidArguments: TuistAcceptanceTestCase {
    func test_with_invalid_arguments() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                let initAnswers = InitPromptAnswers(
                    workflowType: .createGeneratedProject,
                    integrateWithServer: false,
                    generatedProjectPlatform: "ios",
                    generatedProjectName: "MyApp",
                    accountType: .createOrganizationAccount,
                    newOrganizationAccountHandle: "organization"
                )
                try await run(
                    InitCommand.self,
                    "--answers",
                    initAnswers.base64EncodedJSONString(),
                    "--path",
                    temporaryDirectory.pathString
                )
                self.fixturePath = temporaryDirectory.appending(component: "MyApp")
                try await run(InstallCommand.self)
                try await run(GenerateCommand.self)
                await XCTAssertThrowsSpecific(
                    try await run(BuildCommand.self, "MyApp", "--", "-scheme", "MyApp"),
                    XcodeBuildPassthroughArgumentError.alreadyHandled("-scheme")
                )
                await XCTAssertThrowsSpecific(
                    try await run(BuildCommand.self, "MyApp", "--", "-project", "MyApp"),
                    XcodeBuildPassthroughArgumentError.alreadyHandled("-project")
                )
                await XCTAssertThrowsSpecific(
                    try await run(BuildCommand.self, "MyApp", "--", "-workspace", "MyApp"),
                    XcodeBuildPassthroughArgumentError.alreadyHandled("-workspace")
                )
                // SystemError is verbose and would lead to flakyness
                // xcodebuild: error: The flag -addressSanitizerEnabled must be supplied with an argument YES or NO
                await XCTAssertThrows(
                    try await run(BuildCommand.self, "MyApp", "--", "-parallelizeTargets", "YES", "-enableAddressSanitizer")
                )
                // xcodebuild: error: option '-configuration' may only be provided once
                // Usage: xcodebuild [-project <projectname>] ...
                await XCTAssertThrows(
                    try await run(BuildCommand.self, "MyApp", "--configuration", "Debug", "--", "-configuration", "Debug")
                )
            }
        }
    }
}

final class BuildAcceptanceTestAppWithPreviews: TuistAcceptanceTestCase {
    func test_with_previews() async throws {
        try await setUpFixture("generated_app_with_previews")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class BuildAcceptanceTestAppWithFrameworkAndTests: TuistAcceptanceTestCase {
    func test_with_framework_and_tests() async throws {
        try await setUpFixture("generated_app_with_framework_and_tests")
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
//        try await setUpFixture("app_with_tests")
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
        try await setUpFixture("generated_ios_app_with_custom_configuration")
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
        try await setUpFixture("generated_framework_with_swift_macro")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "Framework", "--", "-skipMacroValidation")
    }
}

final class BuildAcceptanceTestFrameworkWithSwiftMacroIntegratedWithXcodeProjPrimitives: TuistAcceptanceTestCase {
    func test_framework_with_swift_macro_integrated_with_xcode_proj_primitives() async throws {
        try await setUpFixture("generated_framework_with_native_swift_macro")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "Framework", "--platform", "macos")
        try await run(BuildCommand.self, "Framework", "--platform", "ios")
    }
}

final class BuildAcceptanceTestMultiplatformAppWithSDK: TuistAcceptanceTestCase {
    func test() async throws {
        try await setUpFixture("generated_multiplatform_app_with_sdk")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "macos")
        try await run(BuildCommand.self, "App", "--platform", "ios")
    }
}

final class BuildAcceptanceTestMultiplatformµFeatureUnitTestsWithExplicitDependencies: TuistAcceptanceTestCase {
    func test() async throws {
        try await setUpFixture("generated_multiplatform_µFeature_unit_tests_with_explicit_dependencies")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "ExampleApp", "--platform", "ios")
        try await run(TestCommand.self, "ModuleA", "--platform", "ios")
    }
}

final class BuildAcceptanceTestMultiplatformAppWithMacrosAndEmbeddedWatchOSApp: TuistAcceptanceTestCase {
    func test() async throws {
        try await setUpFixture("generated_multiplatform_app_with_macros_and_embedded_watchos_app")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "ios")
    }
}

final class BuildAcceptanceTestiOSAppWithCPlusPLusInteroperability: TuistAcceptanceTestCase {
    func test() async throws {
        try await setUpFixture("generated_ios_app_with_cplusplus_interoperability")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "ios")
    }
}

final class XcodeBuildCommandAcceptanceTests: TuistAcceptanceTestCase {
    @Test(
        .withFixture("generated_ios_app_with_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func xcodebuild_build_command() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])

        try await TuistTest.run(
            XcodeBuildBuildCommand.self,
            [
                "build",
                "-workspace",
                fixtureDirectory.pathString + "/App.xcworkspace",
                "-scheme",
                "App",
                "-destination",
                "generic/platform=iOS Simulator",
                "-derivedDataPath",
                temporaryDirectory.pathString,
            ]
        )
    }

    @Test(
        .withFixture("generated_ios_app_with_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func xcodebuild_test_command() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])

        try await TuistTest.run(
            XcodeBuildTestCommand.self,
            [
                "test",
                "-workspace",
                fixtureDirectory.pathString + "/App.xcworkspace",
                "-scheme",
                "App",
                "-destination",
                "generic/platform=iOS Simulator",
                "-derivedDataPath",
                temporaryDirectory.pathString,
            ]
        )
    }

    @Test(
        .withFixture("generated_ios_app_with_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func xcodebuild_build_for_testing_command() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])

        try await TuistTest.run(
            XcodeBuildBuildForTestingCommand.self,
            [
                "build-for-testing",
                "-workspace",
                fixtureDirectory.pathString + "/App.xcworkspace",
                "-scheme",
                "App",
                "-destination",
                "generic/platform=iOS Simulator",
                "-derivedDataPath",
                temporaryDirectory.pathString,
            ]
        )
    }

    @Test(
        .withFixture("generated_ios_app_with_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func xcodebuild_test_without_building_command() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])

        // First build for testing
        try await TuistTest.run(
            XcodeBuildBuildForTestingCommand.self,
            [
                "build-for-testing",
                "-workspace",
                fixtureDirectory.pathString + "/App.xcworkspace",
                "-scheme",
                "App",
                "-destination",
                "generic/platform=iOS Simulator",
                "-derivedDataPath",
                temporaryDirectory.pathString,
            ]
        )

        // Then test without building
        try await TuistTest.run(
            XcodeBuildTestWithoutBuildingCommand.self,
            [
                "test-without-building",
                "-workspace",
                fixtureDirectory.pathString + "/App.xcworkspace",
                "-scheme",
                "App",
                "-destination",
                "generic/platform=iOS Simulator",
                "-derivedDataPath",
                temporaryDirectory.pathString,
            ]
        )
    }

    @Test(
        .withFixture("generated_ios_app_with_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func xcodebuild_archive_command() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])

        try await TuistTest.run(
            XcodeBuildArchiveCommand.self,
            [
                "archive",
                "-workspace",
                fixtureDirectory.pathString + "/App.xcworkspace",
                "-scheme",
                "App",
                "-destination",
                "generic/platform=iOS",
                "-archivePath",
                temporaryDirectory.pathString + "/App.xcarchive",
            ]
        )
    }

    @Test(
        .withFixture("generated_ios_app_with_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func xcodebuild_unordered_build_command() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])

        try await TuistTest.run(
            XcodeBuildCommandReorderer.self,
            [
                "-workspace",
                fixtureDirectory.pathString + "/App.xcworkspace",
                "-scheme",
                "App",
                "-destination",
                "generic/platform=iOS Simulator",
                "-derivedDataPath",
                temporaryDirectory.pathString,
                "build",
            ]
        )
    }
}
