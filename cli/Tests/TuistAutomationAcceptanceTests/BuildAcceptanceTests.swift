import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistSupport
import TuistTesting
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
struct BuildAcceptanceTestWithTemplates {
    @Test(.inTemporaryDirectory, .withMockedDependencies)
    func with_templates() async throws {
        let fileSystem = FileSystem()
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let initAnswers = InitPromptAnswers(
                workflowType: .createGeneratedProject,
                integrateWithServer: false,
                generatedProjectPlatform: "ios",
                generatedProjectName: "MyApp",
                accountType: .createOrganizationAccount,
                newOrganizationAccountHandle: "organization"
            )
            try await TuistTest.run(
                InitCommand.self,
                [
                    "--answers",
                    initAnswers.base64EncodedJSONString(),
                    "--path",
                    temporaryDirectory.pathString,
                ]
            )
            let fixturePath = temporaryDirectory.appending(component: "MyApp")
            try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
            try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixturePath.pathString])
            try await TuistTest.run(
                BuildCommand.self,
                ["--path", fixturePath.pathString, "--derived-data-path", derivedDataPath.pathString]
            )
            try await TuistTest.run(
                BuildCommand.self,
                ["MyApp", "--path", fixturePath.pathString, "--derived-data-path", derivedDataPath.pathString]
            )
            try await TuistTest.run(
                BuildCommand.self,
                ["MyApp", "--configuration", "Debug", "--path", fixturePath.pathString, "--derived-data-path", derivedDataPath.pathString]
            )
            try await TuistTest.run(
                BuildCommand.self,
                [
                    "MyApp",
                    "--path",
                    fixturePath.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-parallelizeTargets",
                    "-enableAddressSanitizer",
                    "YES",
                ]
            )
        }
    }
}

struct BuildAcceptanceTestInvalidArguments {
    @Test(.inTemporaryDirectory, .withMockedDependencies)
    func with_invalid_arguments() async throws {
        let fileSystem = FileSystem()
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let initAnswers = InitPromptAnswers(
                workflowType: .createGeneratedProject,
                integrateWithServer: false,
                generatedProjectPlatform: "ios",
                generatedProjectName: "MyApp",
                accountType: .createOrganizationAccount,
                newOrganizationAccountHandle: "organization"
            )
            try await TuistTest.run(
                InitCommand.self,
                [
                    "--answers",
                    initAnswers.base64EncodedJSONString(),
                    "--path",
                    temporaryDirectory.pathString,
                ]
            )
            let fixturePath = temporaryDirectory.appending(component: "MyApp")
            try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
            try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixturePath.pathString])
            await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-scheme")) {
                try await TuistTest.run(
                    BuildCommand.self,
                    [
                        "MyApp",
                        "--path",
                        fixturePath.pathString,
                        "--derived-data-path",
                        derivedDataPath.pathString,
                        "--",
                        "-scheme",
                        "MyApp",
                    ]
                )
            }
            await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-project")) {
                try await TuistTest.run(
                    BuildCommand.self,
                    [
                        "MyApp",
                        "--path",
                        fixturePath.pathString,
                        "--derived-data-path",
                        derivedDataPath.pathString,
                        "--",
                        "-project",
                        "MyApp",
                    ]
                )
            }
            await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-workspace")) {
                try await TuistTest.run(
                    BuildCommand.self,
                    [
                        "MyApp",
                        "--path",
                        fixturePath.pathString,
                        "--derived-data-path",
                        derivedDataPath.pathString,
                        "--",
                        "-workspace",
                        "MyApp",
                    ]
                )
            }
            await #expect(throws: Error.self) {
                try await TuistTest.run(
                    BuildCommand.self,
                    [
                        "MyApp",
                        "--path",
                        fixturePath.pathString,
                        "--derived-data-path",
                        derivedDataPath.pathString,
                        "--",
                        "-parallelizeTargets",
                        "YES",
                        "-enableAddressSanitizer",
                    ]
                )
            }
            await #expect(throws: Error.self) {
                try await TuistTest.run(
                    BuildCommand.self,
                    [
                        "MyApp",
                        "--configuration",
                        "Debug",
                        "--path",
                        fixturePath.pathString,
                        "--derived-data-path",
                        derivedDataPath.pathString,
                        "--",
                        "-configuration",
                        "Debug",
                    ]
                )
            }
        }
    }
}

struct BuildAcceptanceTestAppWithPreviews {
    @Test(.withFixture("generated_app_with_previews"), .inTemporaryDirectory)
    func with_previews() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct BuildAcceptanceTestAppWithFrameworkAndTests {
    @Test(.withFixture("generated_app_with_framework_and_tests"), .inTemporaryDirectory)
    func with_framework_and_tests() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            BuildCommand.self,
            ["AppCustomScheme", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            BuildCommand.self,
            ["App-Workspace", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
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

struct BuildAcceptanceTestiOSAppWithCustomConfigurationAndBuildToCustomDirectory {
    @Test(.withFixture("generated_ios_app_with_custom_configuration"), .inTemporaryDirectory)
    func ios_app_with_custom_and_build_to_custom_directory() async throws {
        let fixturePath = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixturePath.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            [
                "App",
                "--configuration",
                "debug",
                "--build-output-path",
                fixturePath.appending(component: "Builds").pathString,
                "--path",
                fixturePath.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
        let debugPath = fixturePath.appending(
            try RelativePath(validating: "Builds/debug-iphonesimulator")
        )
        try expectDirectoryContentEqual(debugPath, ["App.app", "App.swiftmodule", "FrameworkA.framework"])
        try await TuistTest.run(
            BuildCommand.self,
            [
                "App",
                "--configuration",
                "release",
                "--build-output-path",
                fixturePath.appending(component: "Builds").pathString,
                "--path",
                fixturePath.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
        try expectDirectoryContentEqual(debugPath, ["App.app", "App.swiftmodule", "FrameworkA.framework"])
        let releasePath = fixturePath.appending(
            try RelativePath(validating: "Builds/release-iphonesimulator")
        )
        try expectDirectoryContentEqual(
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

struct BuildAcceptanceTestFrameworkWithSwiftMacroIntegratedWithStandardMethod {
    @Test(.withFixture("generated_framework_with_swift_macro"), .inTemporaryDirectory)
    func framework_with_swift_macro_integrated_with_standard_method() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            [
                "Framework",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
                "--",
                "-skipMacroValidation",
            ]
        )
    }
}

struct BuildAcceptanceTestFrameworkWithSwiftMacroIntegratedWithXcodeProjPrimitives {
    @Test(.withFixture("generated_framework_with_native_swift_macro"), .inTemporaryDirectory)
    func framework_with_swift_macro_integrated_with_xcode_proj_primitives() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["Framework", "--platform", "macos", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            BuildCommand.self,
            ["Framework", "--platform", "ios", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct BuildAcceptanceTestMultiplatformAppWithSDK {
    @Test(.withFixture("generated_multiplatform_app_with_sdk"), .inTemporaryDirectory)
    func test() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--platform", "macos", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--platform", "ios", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct BuildAcceptanceTestMultiplatformµFeatureUnitTestsWithExplicitDependencies {
    @Test(.withFixture("generated_multiplatform_µFeature_unit_tests_with_explicit_dependencies"), .inTemporaryDirectory)
    func test() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["ExampleApp", "--platform", "ios", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            TestCommand.self,
            ["ModuleA", "--platform", "ios", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct BuildAcceptanceTestMultiplatformAppWithMacrosAndEmbeddedWatchOSApp {
    @Test(.withFixture("generated_multiplatform_app_with_macros_and_embedded_watchos_app"), .inTemporaryDirectory)
    func test() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--platform", "ios", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct BuildAcceptanceTestiOSAppWithCPlusPLusInteroperability {
    @Test(.withFixture("generated_ios_app_with_cplusplus_interoperability"), .inTemporaryDirectory)
    func test() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--platform", "ios", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct XcodeBuildCommandAcceptanceTests {
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
                "-project",
                fixtureDirectory.pathString + "/App.xcodeproj",
                "-scheme",
                "AppTests",
                "-destination",
                "platform=iOS Simulator,name=iPhone 17",
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
                "-project",
                fixtureDirectory.pathString + "/App.xcodeproj",
                "-scheme",
                "AppTests",
                "-destination",
                "platform=iOS Simulator,name=iPhone 17",
                "-derivedDataPath",
                temporaryDirectory.pathString,
            ]
        )

        // Then test without building
        try await TuistTest.run(
            XcodeBuildTestWithoutBuildingCommand.self,
            [
                "test-without-building",
                "-project",
                fixtureDirectory.pathString + "/App.xcodeproj",
                "-scheme",
                "AppTests",
                "-destination",
                "platform=iOS Simulator,name=iPhone 17",
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
