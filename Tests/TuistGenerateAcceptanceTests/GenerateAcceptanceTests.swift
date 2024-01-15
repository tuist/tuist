import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

/// Generate a new project using Tuist (suite 1)
final class GenerateAcceptanceTestiOSAppWithTests: TuistAcceptanceTestCase {
    func test_ios_app_with_tests() async throws {
        try setUpFixture(.iosAppWithTests)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try setUpFixture(.iosAppWithFrameworks)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await XCTAssertProductWithDestinationContainsInfoPlistKey(
            "Framework1.framework",
            destination: "Debug-iphonesimulator",
            key: "Test"
        )
    }
}

final class GenerateAcceptanceTestiOSAppWithHeaders: TuistAcceptanceTestCase {
    func test_ios_app_with_headers() async throws {
        try setUpFixture(.iosAppWithHeaders)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestInvalidWorkspaceManifestName: TuistAcceptanceTestCase {
    func test_invalid_workspace_manifest_name() async throws {
        try setUpFixture(.invalidWorkspaceManifestName)
        do {
            try await run(GenerateCommand.self)
            XCTFail("Generate command should have failed")
        } catch {
            XCTAssertEqual(String(describing: error), "Manifest not found at path \(fixturePath.pathString)")
        }
    }
}

// TODO: Fix (this test has an issue in GitHub actions due to a missing tvOS platform)
// final class GenerateAcceptanceTestiOSAppWithSDK: TuistAcceptanceTestCase {
//    func test_ios_app_with_sdk() async throws {
//        try setUpFixture("ios_app_with_sdk")
//        try await run(GenerateCommand.self)
//        try await run(BuildCommand.self)
//        try await run(BuildCommand.self, "MacFramework", "--platform", "macOS")
//        try await run(BuildCommand.self, "TVFramework", "--platform", "tvOS")
//    }
// }

final class GenerateAcceptanceTestiOSAppWithFrameworkAndResources: TuistAcceptanceTestCase {
    func test_ios_app_with_framework_and_resources() async throws {
        try setUpFixture(.iosAppWithFrameworkAndResources)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        for resource in [
            "tuist.png",
            "Examples/item.json",
            "Examples/list.json",
            "Assets.car",
            "resource.txt",
            "en.lproj/Greetings.strings",
            "fr.lproj/Greetings.strings",
            "resource_without_extension",
            "StaticFrameworkResources.bundle",
            "StaticFramework2Resources.bundle",
            "StaticFramework3_StaticFramework3.bundle",
            "StaticFramework4_StaticFramework4.bundle",
        ] {
            try await XCTAssertProductWithDestinationContainsResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }
        try await XCTAssertProductWithDestinationDoesNotContainResource(
            "App.app",
            destination: "Debug-iphonesimulator",
            resource: "do_not_include.dat"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "StaticFrameworkResources.bundle",
            destination: "Debug-iphonesimulator",
            resource: "tuist-bundle.png"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "StaticFramework2Resources.bundle",
            destination: "Debug-iphonesimulator",
            resource: "StaticFramework2Resources-tuist.png"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "StaticFramework3_StaticFramework3.bundle",
            destination: "Debug-iphonesimulator",
            resource: "StaticFramework3Resources-tuist.png"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "StaticFramework4_StaticFramework4.bundle",
            destination: "Debug-iphonesimulator",
            resource: "StaticFramework4Resources-tuist.png"
        )
        try XCTAssertDirectoryContentEqual(
            fixturePath.appending(components: "App", "Derived", "Sources"),
            [
                "TuistBundle+App.swift",
                "TuistStrings+App.swift",
                "TuistAssets+App.swift",
                "TuistFonts+App.swift",
                "TuistPlists+App.swift",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            fixturePath.appending(components: "StaticFramework3", "Derived", "Sources"),
            [
                "TuistAssets+StaticFramework3.swift",
                "TuistBundle+StaticFramework3.swift",
            ]
        )
        try XCTAssertProductWithDestinationDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
    }
}

final class GenerateAcceptanceTestIosAppWithCustomDevelopmentRegion: TuistAcceptanceTestCase {
    func test_ios_app_with_custom_development_region() async throws {
        try setUpFixture(.iosAppWithCustomDevelopmentRegion)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        for resource in [
            "en.lproj/Greetings.strings",
            "fr.lproj/Greetings.strings",
            "fr-CA.lproj/Greetings.strings",
        ] {
            try await XCTAssertProductWithDestinationContainsResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }

        XCTAssertTrue(
            try FileHandler.shared.readTextFile(
                fixturePath.appending(components: "Derived", "Sources", "TuistStrings+App.swift")
            )
            .contains(
                """
                public static let evening = AppStrings.tr("Greetings", "evening")
                """
            )
        )
    }
}

final class GenerateAcceptanceTestiOSAppWithCustomResourceParserOptions: TuistAcceptanceTestCase {
    func test_ios_app_with_custom_resource_parser_options() async throws {
        try setUpFixture(.iosWppWithCustomResourceParserOptions)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        for resource in [
            "en.lproj/Greetings.strings",
            "fr.lproj/Greetings.strings",
        ] {
            try await XCTAssertProductWithDestinationContainsResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }

        XCTAssertTrue(
            try FileHandler.shared.readTextFile(
                fixturePath.appending(components: "Derived", "Sources", "TuistStrings+App.swift")
            )
            .contains(
                """
                public static let evening = AppStrings.tr("Greetings", "Good/evening")
                """
            )
        )
        XCTAssertTrue(
            try FileHandler.shared.readTextFile(
                fixturePath.appending(components: "Derived", "Sources", "TuistStrings+App.swift")
            )
            .contains(
                """
                public static let morning = AppStrings.tr("Greetings", "Good/morning")
                """
            )
        )
    }
}

final class GenerateAcceptanceTestiOSAppWithFrameworkLinkingStaticFramework: TuistAcceptanceTestCase {
    func test_ios_app_with_framework_linking_static_framework() async throws {
        try setUpFixture(.iosAppWithFrameworkLinkingStaticFramework)
        try await run(BuildCommand.self)

        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-iphonesimulator",
            resource: "Frameworks/Framework1.framework/Framework1"
        )
        for resource in [
            "Frameworks/Framework2.framework/Framework2",
            "Frameworks/Framework3.framework/Framework3",
            "Frameworks/Framework4.framework/Framework4",
        ] {
            try await XCTAssertProductWithDestinationDoesNotContainResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }
        try XCTAssertProductWithDestinationDoesNotContainHeaders("App.app", destination: "Debug-iphonesimulator")
    }
}

final class GenerateAcceptanceTestsiOSAppWithCustomScheme: TuistAcceptanceTestCase {
    func test_ios_app_with_custom_scheme() async throws {
        try setUpFixture(.iosAppWithCustomScheme)
        try await run(BuildCommand.self)
        try await run(BuildCommand.self, "App-Debug")
        try await run(BuildCommand.self, "App-Release")
        try await run(BuildCommand.self, "App-Local")
    }
}

final class GenerateAcceptanceTestiOSAppWithLocalSwiftPackage: TuistAcceptanceTestCase {
    func test_ios_app_with_local_swift_package() async throws {
        try setUpFixture(.iosAppWithLocalSwiftPackage)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestiOSAppWithMultiConfigs: TuistAcceptanceTestCase {
    func test_ios_app_with_multi_configs() async throws {
        try setUpFixture(.iosAppWithMultiConfigs)
        try await run(GenerateCommand.self)
        try await XCTAssertSchemeContainsBuildSettings(
            "App",
            configuration: "Debug",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Debug"
        )
        try await XCTAssertSchemeContainsBuildSettings(
            "App",
            configuration: "Beta",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Beta"
        )
        try await XCTAssertSchemeContainsBuildSettings(
            "App",
            configuration: "Release",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Release"
        )
        try await XCTAssertSchemeContainsBuildSettings(
            "Framework2",
            configuration: "Debug",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Debug"
        )
        try await XCTAssertSchemeContainsBuildSettings(
            "Framework2",
            configuration: "Beta",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Target.Beta"
        )
        try await XCTAssertSchemeContainsBuildSettings(
            "Framework2",
            configuration: "Release",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Release"
        )
    }
}

final class GenerateAcceptanceTestiOSAppWithIncompatibleXcode: TuistAcceptanceTestCase {
    func test_ios_app_with_incompatible_xcode() async throws {
        try setUpFixture(.iosAppWithIncompatibleXcode)
        do {
            try await run(GenerateCommand.self)
            XCTFail("Generate should have failed")
        } catch {
            XCTAssertStandardError(
                pattern: "which is not compatible with this project's Xcode version requirement of 3.2.1."
            )
            XCTAssertEqual(
                (error as? FatalError)?.description,
                "Fatal linting issues found"
            )
        }
    }
}

// TODO: Find a different build tool plugin. SwiftLintPlugin imports swift-syntax that takes a _very_ long time to build
// final class GenerateAcceptanceTestiOSAppWithActions: TuistAcceptanceTestCase {
//    func test_ios_app_with_actions() async throws {
//        try setUpFixture("ios_app_with_actions")
//        try await run(GenerateCommand.self)
//        try await run(BuildCommand.self)
//
//        let xcodeproj = try XcodeProj(
//            pathString: fixturePath.appending(components: "App", "App.xcodeproj").pathString
//        )
//        let target = try XCTUnwrapTarget("App", in: xcodeproj)
//        let buildPhases = target.buildPhases
//
//        XCTAssertEqual(
//            buildPhases.first?.name(),
//            "Tuist"
//        )
//        XCTAssertEqual(
//            buildPhases.last?.name(),
//            "Rocks"
//        )
//        let phaseWithDependency = try XCTUnwrap(
//            buildPhases
//                .first(where: { $0.name() == "PhaseWithDependency" })
//                as? PBXShellScriptBuildPhase
//        )
//        XCTAssertEqual(phaseWithDependency.dependencyFile, "$TEMP_DIR/dependencies.d")
//
//        let appWithSpaceXcodeproj = try XcodeProj(
//            pathString: fixturePath.appending(components: "App With Space", "AppWithSpace.xcodeproj").pathString
//        )
//        let appWithSpaceTarget = try XCTUnwrapTarget("AppWithSpace", in: appWithSpaceXcodeproj)
//        XCTAssertEqual(
//            appWithSpaceTarget.buildPhases.first?.name(),
//            "Run script"
//        )
//    }
// }

final class GenerateAcceptanceTestiOSAppWithBuildVariables: TuistAcceptanceTestCase {
    func test_ios_app_with_build_variables() async throws {
        try setUpFixture(.iosAppWithBuildVariables)
        try await run(GenerateCommand.self)
        let xcodeproj = try XcodeProj(
            pathString: fixturePath.appending(components: "App", "App.xcodeproj").pathString
        )
        let target = try XCTUnwrapTarget("App", in: xcodeproj)
        let buildPhases = target.buildPhases

        XCTAssertEqual(
            buildPhases.first?.name(),
            "Tuist"
        )
        XCTAssertEqual(
            (buildPhases.first as? PBXShellScriptBuildPhase)?.outputPaths,
            ["$(DERIVED_FILE_DIR)/output.txt"]
        )
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestiOSAppWithRemoteSwiftPackage: TuistAcceptanceTestCase {
    func test_ios_app_with_remote_swift_package() async throws {
        try setUpFixture(.iosAppWithRemoteSwiftPackage)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestVisionOSAppWithRemoteSwiftPackage: TuistAcceptanceTestCase {
    func test_visionos_app() async throws {
        try setUpFixture(.visionosApp)
        try await run(GenerateCommand.self)
//        TODO: Fix
//        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestiOSAppWithLocalBinarySwiftPackage: TuistAcceptanceTestCase {
    func test_ios_app_with_local_binary_swift_package() async throws {
        try setUpFixture(.iosAppWithLocalBinarySwiftPackage)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestiOSAppWithExtensions: TuistAcceptanceTestCase {
    func test_ios_app_with_extensions() async throws {
        try setUpFixture(.iosAppWithExtensions)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")

        try await XCTAssertProductWithDestinationContainsExtension(
            "App.app",
            destination: "Debug-iphonesimulator",
            extension: "StickersPackExtension"
        )
        try await XCTAssertProductWithDestinationContainsExtension(
            "App.app",
            destination: "Debug-iphonesimulator",
            extension: "NotificationServiceExtension"
        )
        try await XCTAssertProductWithDestinationContainsExtensionKitExtension(
            "App.app",
            destination: "Debug-iphonesimulator",
            extension: "AppIntentExtension"
        )
        try XCTAssertProductWithDestinationDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
    }
}

// TODO: Fix – tvOS
// final class GenerateAcceptanceTestTvOSAppWithExtensions: TuistAcceptanceTestCase {
//    func test_tvos_app_with_extensions() async throws {
//        try setUpFixture("tvos_app_with_extensions")
//        try await run(GenerateCommand.self)
//        try await run(BuildCommand.self)
//        try await XCTAssertProductWithDestinationContainsExtension(
//            "App.app",
//            destination: "Debug-appletvsimulator",
//            extension: "TopShelfExtension"
//        )
//        try XCTAssertProductWithDestinationDoesNotContainHeaders(
//            "App.app",
//            destination: "Debug-appletvsimulator"
//        )
//    }
// }

final class GenerateAcceptanceTestiOSAppWithWatchApp2: TuistAcceptanceTestCase {
    func test_ios_app_with_watchapp2() async throws {
        try setUpFixture(.iosAppWithWatchapp2)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-iphonesimulator",
            resource: "Watch/WatchApp.app"
        )
        try await XCTAssertProductWithDestinationContainsExtension(
            "WatchApp.app",
            destination: "Debug-watchsimulator",
            extension: "WatchAppExtension"
        )
        try XCTAssertProductWithDestinationDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
        try XCTAssertProductWithDestinationDoesNotContainHeaders(
            "WatchApp.app",
            destination: "Debug-watchsimulator"
        )
    }
}

final class GenerateAcceptanceTestInvalidManifest: TuistAcceptanceTestCase {
    func test_invalid_manifest() async throws {
        try setUpFixture(.invalidManifest)
        do {
            try await run(GenerateCommand.self)
            XCTFail("Generate command should have failed")
        } catch let error as FatalError {
            XCTAssertTrue(error.description.contains("error: expected ',' separator"))
        }
    }
}

final class GenerateAcceptanceTestiOSAppLarge: TuistAcceptanceTestCase {
    func test_ios_app_large() async throws {
        try setUpFixture(.iosAppLarge)
        try await run(GenerateCommand.self)
    }
}

final class GenerateAcceptanceTestiOSWorkspaceWithDependencyCycle: TuistAcceptanceTestCase {
    func test_ios_workspace_with_dependency_cycle() async throws {
        try setUpFixture(.iosWorkspaceWithDependencyCycle)
        do {
            try await run(GenerateCommand.self)
            XCTFail("Generate command should have failed")
        } catch let error as FatalError {
            XCTAssertTrue(error.description.contains("Found circular dependency between targets"))
        }
    }
}

final class GenerateAcceptanceTestFrameworkWithEnvironmentVariables: TuistAcceptanceTestCase {
    func test_framework_with_environment_variables() async throws {
        try setUpFixture(.frameworkWithEnvironmentVariables)
        environment.manifestLoadingVariables["TUIST_FRAMEWORK_NAME"] = "FrameworkA"
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "FrameworkA")
        environment.manifestLoadingVariables["TUIST_FRAMEWORK_NAME"] = "FrameworkB"
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "FrameworkB")
    }
}

final class GenerateAcceptanceTestiOSAppWithCoreData: TuistAcceptanceTestCase {
    func test_ios_app_with_coredata() async throws {
        try setUpFixture(.iosAppWithCoreData)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        for resource in [
            "Users.momd",
            "Unversioned.momd",
            "UsersAutoDetect.momd",
            "1_2.cdm",
        ] {
            try await XCTAssertProductWithDestinationContainsResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }
    }
}

final class GenerateAcceptanceTestiOSAppWithAppClip: TuistAcceptanceTestCase {
    func test_ios_app_with_appclip() async throws {
        try setUpFixture(.iosAppWithAppClip)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await XCTAssertProductWithDestinationContainsAppClipWithArchitecture(
            "App.app",
            destination: "Debug-iphonesimulator",
            appClip: "AppClip1",
            architecture: "x86_64"
        )
        try XCTAssertFrameworkEmbedded("Framework", by: "AppClip1")
    }
}

final class GenerateAcceptanceTestCommandLineToolBase: TuistAcceptanceTestCase {
    func test_command_line_tool_basic() async throws {
        try setUpFixture(.commandLineToolBasic)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

final class GenerateAcceptanceTestCommandLineToolWithStaticLibrary: TuistAcceptanceTestCase {
    func test_command_line_tool_with_static_library() async throws {
        try setUpFixture(.commandLineToolWithStaticLibrary)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

final class GenerateAcceptanceTestCommandLineToolWithDynamicLibrary: TuistAcceptanceTestCase {
    func test_command_line_tool_with_dynamic_library() async throws {
        try setUpFixture(.commandLineToolWithDynamicLibrary)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

final class GenerateAcceptanceTestCommandLineToolWithDynamicFramework: TuistAcceptanceTestCase {
    func test_command_line_tool_with_dynamic_framework() async throws {
        try setUpFixture(.commandLineToolWithDynamicFramework)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

final class GenerateAcceptanceTestmacOSAppWithCopyFiles: TuistAcceptanceTestCase {
    func test_macos_app_with_copy_files() async throws {
        try setUpFixture(.macosAppWithCopyFiles)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)

        let xcodeproj = try XcodeProj(
            pathString: xcodeprojPath.pathString
        )
        let target = try XCTUnwrapTarget("App", in: xcodeproj)
        let buildPhases = target.buildPhases

        XCTAssertTrue(
            buildPhases.contains(where: { $0.name() == "Copy Templates" })
        )
    }
}

final class GenerateAcceptanceTestManifestWithLogs: TuistAcceptanceTestCase {
    func test_manifest_with_logs() async throws {
        try setUpFixture(.manifestWithLogs)
        try await run(GenerateCommand.self)
        XCTAssertStandardOutput(pattern: "Target name - App")
    }
}

final class GenerateAcceptanceTestProjectWithFileHeaderTemplate: TuistAcceptanceTestCase {
    func test_project_with_file_header_template() async throws {
        try setUpFixture(.projectWithFileHeaderTemplate)
        try await run(GenerateCommand.self)
        XCTAssertTrue(
            FileHandler.shared.exists(
                xcodeprojPath.appending(
                    components: [
                        "xcshareddata",
                        "IDETemplateMacros.plist",
                    ]
                )
            )
        )
    }
}

final class GenerateAcceptanceTestProjectWithInlineFileHeaderTemplate: TuistAcceptanceTestCase {
    func test_project_with_inline_file_header_template() async throws {
        try setUpFixture(.projectWithInlineFileHeaderTemplate)
        try await run(GenerateCommand.self)
        XCTAssertTrue(
            FileHandler.shared.exists(
                xcodeprojPath.appending(
                    components: [
                        "xcshareddata",
                        "IDETemplateMacros.plist",
                    ]
                )
            )
        )
    }
}

final class GenerateAcceptanceTestWorkspaceWithFileHeaderTemplate: TuistAcceptanceTestCase {
    func test_workspace_with_file_header_template() async throws {
        try setUpFixture(.workspaceWithFileHeaderTemplate)
        try await run(GenerateCommand.self)
        XCTAssertTrue(
            FileHandler.shared.exists(
                workspacePath.appending(
                    components: [
                        "xcshareddata",
                        "IDETemplateMacros.plist",
                    ]
                )
            )
        )
    }
}

final class GenerateAcceptanceTestWorkspaceWithInlineFileHeaderTemplate: TuistAcceptanceTestCase {
    func test_workspace_with_inline_file_header_template() async throws {
        try setUpFixture(.workspaceWithInlineFileHeaderTemplate)
        try await run(GenerateCommand.self)
        XCTAssertTrue(
            FileHandler.shared.exists(
                workspacePath.appending(
                    components: [
                        "xcshareddata",
                        "IDETemplateMacros.plist",
                    ]
                )
            )
        )
    }
}

final class GenerateAcceptanceTestiOSAppWithFrameworkAndDisabledResources: TuistAcceptanceTestCase {
    func test_ios_app_with_framework_and_disabled_resources() async throws {
        try setUpFixture(.iosAppWithFrameworkAndDisabledResources)
        try await run(GenerateCommand.self)
        XCTAssertFalse(
            FileHandler.shared.exists(
                fixturePath.appending(
                    components: [
                        "App",
                        "Derived",
                        "Sources",
                        "TuistBundle+App.swift",
                    ]
                )
            )
        )
        XCTAssertFalse(
            FileHandler.shared.exists(
                fixturePath.appending(
                    components: [
                        "Framework1",
                        "Derived",
                        "Sources",
                        "TuistBundle+Framework1.swift",
                    ]
                )
            )
        )
        XCTAssertFalse(
            FileHandler.shared.exists(
                fixturePath.appending(
                    components: [
                        "StaticFramework",
                        "Derived",
                        "Sources",
                        "TuistBundle+StaticFramework.swift",
                    ]
                )
            )
        )
    }
}

final class GenerateAcceptanceTestmacOSAppWithExtensions: TuistAcceptanceTestCase {
    func test_macos_app_with_extensions() async throws {
        try setUpFixture(.macosAppWithExtensions)
        let sdkPkgPath = sourceRootPath
            .appending(
                components: [
                    "fixtures",
                    "resources",
                    "WorkflowExtensionsSDK.pkg",
                ]
            )
        if try !FileHandler.shared.exists(
            AbsolutePath(validating: "/Library/Developer/SDKs/WorkflowExtensionSDK.sdk")
        ) {
            try System.shared.run(["sudo", "installer", "-package", sdkPkgPath.pathString, "-target", "/"])
        }

        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestiOSAppWithImplicitDependencies: TuistAcceptanceTestCase {
    func test_ios_app_with_implicit_dependencies() async throws {
        try setUpFixture(.iosAppWithImplicitDependencies)
        try await run(BuildCommand.self, "FrameworkC")
        do {
            try await run(BuildCommand.self, "App")
            XCTFail("Building app should fail as FrameworkA has an implicit dependency on FrameworkB")
        } catch let error as FatalError {
            XCTAssertTrue(
                error.description.contains("The 'xcodebuild' command exited with error code 65 and message")
            )
        }
    }
}

extension TuistAcceptanceTestCase {
    private func resourcePath(
        for productName: String,
        destination: String,
        resource: String
    ) throws -> AbsolutePath {
        let productPath = try productPath(for: productName, destination: destination)
        if let resource = FileHandler.shared.glob(productPath, glob: "**/\(resource)").first {
            return resource
        } else {
            XCTFail("Could not find resource \(resource) for product \(productName) and destination \(destination)")
            throw XCTUnwrapError.nilValueDetected
        }
    }

    func XCTAssertSchemeContainsBuildSettings(
        _ scheme: String,
        configuration: String,
        buildSettingKey: String,
        buildSettingValue: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let buildSettings = try await System.shared.runAndCollectOutput(
            [
                "/usr/bin/xcodebuild",
                "-scheme",
                scheme,
                "-workspace",
                workspacePath.pathString,
                "-configuration",
                configuration,
                "-showBuildSettings",
            ]
        )

        guard buildSettings.standardOutput.contains("\(buildSettingKey) = \"\(buildSettingValue)\"")
        else {
            XCTFail(
                "Couldn't find \(buildSettingKey) = \(buildSettingValue) for scheme \(scheme) and configuration \(configuration)",
                file: file,
                line: line
            )
            return
        }
    }

    func XCTAssertProductWithDestinationContainsAppClipWithArchitecture(
        _ product: String,
        destination: String,
        appClip: String,
        architecture: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let productPath = try productPath(
            for: product,
            destination: destination
        )

        guard let appClipPath = FileHandler.shared.glob(productPath, glob: "AppClips/\(appClip).app").first,
              FileHandler.shared.exists(appClipPath)
        else {
            XCTFail(
                "App clip \(appClip) not found for product \(product) and destination \(destination)",
                file: file,
                line: line
            )
            return
        }

        let fileInfo = try await System.shared.runAndCollectOutput(
            [
                "file",
                appClipPath.appending(component: appClip).pathString,
            ]
        )
        XCTAssertTrue(fileInfo.standardOutput.contains(architecture))
    }

    func XCTAssertProductWithDestinationContainsExtension(
        _ product: String,
        destination: String,
        extension: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let productPath = try productPath(
            for: product,
            destination: destination
        )

        guard let extensionPath = FileHandler.shared.glob(productPath, glob: "Plugins/\(`extension`).appex").first,
              FileHandler.shared.exists(extensionPath)
        else {
            XCTFail(
                "Extension \(`extension`) not found for product \(product) and destination \(destination)",
                file: file,
                line: line
            )
            return
        }
    }

    func XCTAssertProductWithDestinationContainsExtensionKitExtension(
        _ product: String,
        destination: String,
        extension: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let productPath = try productPath(
            for: product,
            destination: destination
        )

        guard let extensionPath = FileHandler.shared.glob(productPath, glob: "Extensions/\(`extension`).appex").first,
              FileHandler.shared.exists(extensionPath)
        else {
            XCTFail(
                "ExtensionKit \(`extension`) not found for product \(product) and destination \(destination)",
                file: file,
                line: line
            )
            return
        }
    }

    fileprivate func XCTAssertProductWithDestinationContainsResource(
        _ product: String,
        destination: String,
        resource: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let resourcePath = try resourcePath(
            for: product,
            destination: destination,
            resource: resource
        )

        if !FileHandler.shared.exists(resourcePath) {
            XCTFail(
                "Resource \(resource) not found for product \(product) and destination \(destination)",
                file: file,
                line: line
            )
        }
    }

    fileprivate func XCTAssertProductWithDestinationDoesNotContainResource(
        _ product: String,
        destination: String,
        resource: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let productPath = try productPath(for: product, destination: destination)
        if !FileHandler.shared.glob(productPath, glob: "**/\(resource)").isEmpty {
            XCTFail("Resource \(resource) found for product \(product) and destination \(destination)", file: file, line: line)
        }
    }

    fileprivate func XCTAssertProductWithDestinationContainsInfoPlistKey(
        _ product: String,
        destination: String,
        key: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let infoPlistPath = try resourcePath(
            for: product,
            destination: destination,
            resource: "Info.plist"
        )
        let output = try await System.shared.runAndCollectOutput(
            [
                "/usr/libexec/PlistBuddy",
                "-c",
                "print :\(key)",
                infoPlistPath.pathString,
            ]
        )

        if output.standardOutput.isEmpty {
            XCTFail(
                "Key \(key) not found in the \(product) Info.plist",
                file: file,
                line: line
            )
        }
    }
}
