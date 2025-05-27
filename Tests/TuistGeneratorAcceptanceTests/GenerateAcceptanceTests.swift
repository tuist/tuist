import Path
import Testing
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

struct GeneratorAcceptanceTests {
    @Test(.withFixture("app_with_framework_and_tests")) func app_with_framework_and_tests() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")

        // When
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])

        // Then
        try TuistTest.expectFrameworkNotEmbedded("Framework", by: "AppExtension", inXcodeProj: xcodeprojPath)
    }

    @Test(.withFixture("app_with_exponea_sdk"), .withMockedLogger()) func test_app_with_exponea_sdk() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)

        // When
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
    }

    @Test(
        .withFixture("framework_with_environment_variables"),
        .withMockedLogger(),
        .withMockedEnvironment()
    ) func framework_with_environment_variables() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.manifestLoadingVariables["TUIST_FRAMEWORK_NAME"] = "FrameworkA"
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)

        // When
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        try await TuistTest.run(BuildCommand.self, ["FrameworkA", "--path", fixtureDirectory.pathString])

        mockEnvironment.manifestLoadingVariables["TUIST_FRAMEWORK_NAME"] = "FrameworkB"
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        try await TuistTest.run(BuildCommand.self, ["FrameworkB", "--path", fixtureDirectory.pathString])
    }
}

final class GenerateAcceptanceTestiOSAppWithTests: TuistAcceptanceTestCase {
    func test_ios_app_with_tests() async throws {
        try await setUpFixture(.iosAppWithTests)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }

    func test_focused_targets() async throws {
        func generatedTargets() throws -> [String] {
            try XcodeProj(pathString: xcodeprojPath.pathString).pbxproj.nativeTargets.map(\.name).sorted()
        }

        try await setUpFixture(.iosAppWithTests)
        try await run(GenerateCommand.self)
        XCTAssertEqual(
            try generatedTargets(),
            [
                "App",
                "App-dash",
                "App-dashUITests",
                "AppCore",
                "AppCoreTests",
                "AppTests",
                "AppUITests",
                "MacFramework",
                "MacFrameworkTests",
            ]
        )
        try await run(GenerateCommand.self, "AppCore")
        XCTAssertEqual(try generatedTargets(), ["AppCore"])
    }
}

final class GenerateAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
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
        try await setUpFixture(.iosAppWithHeaders)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestInvalidWorkspaceManifestName: TuistAcceptanceTestCase {
    func test_invalid_workspace_manifest_name() async throws {
        try await setUpFixture(.invalidWorkspaceManifestName)
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
//        try await setUpFixture("ios_app_with_sdk")
//        try await run(GenerateCommand.self)
//        try await run(BuildCommand.self)
//        try await run(BuildCommand.self, "MacFramework", "--platform", "macOS")
//        try await run(BuildCommand.self, "TVFramework", "--platform", "tvOS")
//    }
// }

final class GenerateAcceptanceTestiOSAppWithFrameworkAndResources: TuistAcceptanceTestCase {
    func test_ios_app_with_framework_and_resources() async throws {
        try await setUpFixture(.iosAppWithFrameworkAndResources)
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
        ] {
            try await XCTAssertProductWithDestinationContainsResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }
        for resource in [
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
        try await XCTAssertProductWithDestinationDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
        try XCTAssertDirectoryContentEqual(
            fixturePath.appending(components: "App", "Derived", "PrivacyManifests", "App"),
            [
                "PrivacyInfo.xcprivacy",
            ]
        )
    }
}

final class GenerateAcceptanceTestiOSAppWithOnDemandResources: TuistAcceptanceTestCase {
    func test_ios_app_with_on_demand_resources() async throws {
        try await setUpFixture(.iosAppWithOnDemandResources)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        let pbxprojPath = xcodeprojPath.appending(component: "project.pbxproj")
        let data = try Data(contentsOf: pbxprojPath.url)
        let pbxProj = try PBXProj(data: data)
        let attributes = try XCTUnwrap(pbxProj.projects.first?.attributes)
        let knownAssetTags = try XCTUnwrap(attributes["KnownAssetTags"]?.arrayValue)
        let givenTags = [
            "ar-resource-group",
            "cube-texture",
            "data",
            "data file",
            "datafile",
            "datafolder",
            "image",
            "image-stack",
            "json",
            "nestedimage",
            "newfolder",
            "sprite",
            "tag with space",
            "texture",
        ]
        XCTAssertEqual(knownAssetTags, givenTags)
    }
}

final class GenerateAcceptanceTestiOSAppWithPrivacyManifest: TuistAcceptanceTestCase {
    func test_ios_app_with_privacy_manifest() async throws {
        try await setUpFixture(.iosAppWithPrivacyManifest)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try XCTAssertDirectoryContentEqual(
            fixturePath.appending(components: "Derived", "PrivacyManifests", "MyApp"),
            [
                "PrivacyInfo.xcprivacy",
            ]
        )
    }
}

final class GenerateAcceptanceTestIosAppWithCustomDevelopmentRegion: TuistAcceptanceTestCase {
    func test_ios_app_with_custom_development_region() async throws {
        try await setUpFixture(.iosAppWithCustomDevelopmentRegion)
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
        try await setUpFixture(.iosWppWithCustomResourceParserOptions)
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
        try await setUpFixture(.iosAppWithFrameworkLinkingStaticFramework)
        try await run(GenerateCommand.self)
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
        try await XCTAssertProductWithDestinationDoesNotContainHeaders("App.app", destination: "Debug-iphonesimulator")
    }
}

final class GenerateAcceptanceTestsiOSAppWithCustomScheme: TuistAcceptanceTestCase {
    func test_ios_app_with_custom_scheme() async throws {
        try await setUpFixture(.iosAppWithCustomScheme)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await run(BuildCommand.self, "App-Debug")
        try await run(BuildCommand.self, "App-Release")
        try await run(BuildCommand.self, "App-Local")

        let xcodeprojPath = fixturePath.appending(components: ["App", "MainApp.xcodeproj"])

        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)

        let scheme = try XCTUnwrap(
            xcodeproj.sharedData?.schemes
                .filter { $0.name == "App-Debug" }
                .first
        )

        let testableTarget = try XCTUnwrap(
            scheme.testAction?.testables
                .filter { $0.buildableReference.blueprintName == "AppTests" }
                .first
        )

        XCTAssertEqual(testableTarget.parallelization, .all)

        try XCTAssertContainsSimulatedLocation(
            xcodeprojPath: xcodeprojPath,
            scheme: "App-Debug",
            testTarget: "AppTests",
            simulatedLocation: "Rio de Janeiro, Brazil"
        )
        try XCTAssertContainsSimulatedLocation(
            xcodeprojPath: xcodeprojPath,
            scheme: "App-Release",
            testTarget: "AppTests",
            simulatedLocation: "Grand Canyon.gpx"
        )
    }
}

final class GenerateAcceptanceTestiOSAppWithLocalSwiftPackage: TuistAcceptanceTestCase {
    func test_ios_app_with_local_swift_package() async throws {
        try await setUpFixture(.iosAppWithLocalSwiftPackage)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestiOSAppWithMultiConfigs: TuistAcceptanceTestCase {
    func test_ios_app_with_multi_configs() async throws {
        try await setUpFixture(.iosAppWithMultiConfigs)
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
        try await withMockedDependencies {
            try await setUpFixture(.iosAppWithIncompatibleXcode)
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
}

// TODO: Find a different build tool plugin. SwiftLintPlugin imports swift-syntax that takes a _very_ long time to build
// final class GenerateAcceptanceTestiOSAppWithActions: TuistAcceptanceTestCase {
//    func test_ios_app_with_actions() async throws {
//        try await setUpFixture("ios_app_with_actions")
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
        try await setUpFixture(.iosAppWithBuildVariables)
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
        try await setUpFixture(.iosAppWithRemoteSwiftPackage)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestVisionOSAppWithRemoteSwiftPackage: TuistAcceptanceTestCase {
    func test_visionos_app() async throws {
        try await setUpFixture(.visionosApp)
        try await run(GenerateCommand.self)
//        TODO: Fix
//        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestiOSAppWithLocalBinarySwiftPackage: TuistAcceptanceTestCase {
    func test_ios_app_with_local_binary_swift_package() async throws {
        try await setUpFixture(.iosAppWithLocalBinarySwiftPackage)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestiOSAppWithExtensions: TuistAcceptanceTestCase {
    func test_ios_app_with_extensions() async throws {
        try await setUpFixture(.iosAppWithExtensions)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")

        let xcodeproj = try XcodeProj(
            pathString: xcodeprojPath.pathString
        )
        let target = try XCTUnwrapTarget("App", in: xcodeproj)
        let sourceFileNames = try target.sourceFiles().compactMap(\.path)

        XCTAssertTrue(
            sourceFileNames.contains(where: { $0.hasSuffix("Documentation.docc") }),
            "Expected Documentation to be included in generated project"
        )

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
        try await XCTAssertProductWithDestinationDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "WidgetExtension.appex",
            destination: "Debug-iphonesimulator",
            resource: "Bundle.bundle/dummy.jpg"
        )
    }
}

// TODO: Fix – tvOS
// final class GenerateAcceptanceTestTvOSAppWithExtensions: TuistAcceptanceTestCase {
//    func test_tvos_app_with_extensions() async throws {
//        try await setUpFixture("tvos_app_with_extensions")
//        try await run(GenerateCommand.self)
//        try await run(BuildCommand.self)
//        try await XCTAssertProductWithDestinationContainsExtension(
//            "App.app",
//            destination: "Debug-appletvsimulator",
//            extension: "TopShelfExtension"
//        )
//        try await XCTAssertProductWithDestinationDoesNotContainHeaders(
//            "App.app",
//            destination: "Debug-appletvsimulator"
//        )
//    }
// }

final class GenerateAcceptanceTestiOSAppWithWatchApp2: TuistAcceptanceTestCase {
    func test_ios_app_with_watchapp2() async throws {
        try await setUpFixture(.iosAppWithWatchapp2)
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
        try await XCTAssertProductWithDestinationDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
        try await XCTAssertProductWithDestinationDoesNotContainHeaders(
            "WatchApp.app",
            destination: "Debug-watchsimulator"
        )
    }
}

final class GenerateAcceptanceTestInvalidManifest: TuistAcceptanceTestCase {
    func test_invalid_manifest() async throws {
        try await setUpFixture(.invalidManifest)
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
        try await setUpFixture(.iosAppLarge)
        try await run(GenerateCommand.self)
    }
}

final class GenerateAcceptanceTestiOSWorkspaceWithDependencyCycle: TuistAcceptanceTestCase {
    func test_ios_workspace_with_dependency_cycle() async throws {
        try await setUpFixture(.iosWorkspaceWithDependencyCycle)
        do {
            try await run(GenerateCommand.self)
            XCTFail("Generate command should have failed")
        } catch let error as FatalError {
            XCTAssertTrue(error.description.contains("Found circular dependency between targets"))
        }
    }
}

final class GenerateAcceptanceTestiOSAppWithCoreData: TuistAcceptanceTestCase {
    func test_ios_app_with_coredata() async throws {
        try await setUpFixture(.iosAppWithCoreData)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        for resource in [
            "Users.momd",
            "Unversioned.momd",
            "UsersAutoDetect.momd",
        ] {
            try await XCTAssertProductWithDestinationContainsResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }
        let exists = try await fileSystem.exists(
            fixturePath.appending(
                components: [
                    "Derived",
                    "Sources",
                    "TuistCoreData+App.swift",
                ]
            )
        )
        XCTAssertTrue(exists)
    }
}

final class GenerateAcceptanceTestiOSAppWithAppClip: TuistAcceptanceTestCase {
    func test_ios_app_with_appclip() async throws {
        try await setUpFixture(.iosAppWithAppClip)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await XCTAssertProductWithDestinationContainsAppClipWithArchitecture(
            "App.app",
            destination: "Debug-iphonesimulator",
            appClip: "AppClip1",
            architecture: "arm64"
        )
        try XCTAssertFrameworkEmbedded("Framework", by: "AppClip1")
        try await XCTAssertProductWithDestinationContainsAppClipWithArchitecture(
            "App.app",
            destination: "Debug-iphonesimulator",
            appClip: "AppClip1",
            architecture: "arm64"
        )
        try XCTAssertFrameworkEmbedded("Framework", by: "AppClip1")
        try await XCTAssertProductWithDestinationContainsExtension(
            "AppClip1.app",
            destination: "Debug-iphonesimulator",
            extension: "AppClip1Widgets"
        )
    }
}

final class GenerateAcceptanceTestCommandLineToolBase: TuistAcceptanceTestCase {
    func test_command_line_tool_basic() async throws {
        try await setUpFixture(.commandLineToolBasic)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

final class GenerateAcceptanceTestGeneratedBundleWithMetalFiles: TuistAcceptanceTestCase {
    func test_generated_bundle_with_metal_files() async throws {
        try await setUpFixture(.generatedBunleWithMetalFiles)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "Bundle")
        try await XCTAssertProductWithDestinationContainsResource(
            "Bundle.bundle",
            destination: "Debug-iphonesimulator",
            resource: "default.metallib"
        )
    }
}

final class GenerateAcceptanceTestCommandLineToolWithStaticLibrary: TuistAcceptanceTestCase {
    func test_command_line_tool_with_static_library() async throws {
        try await setUpFixture(.commandLineToolWithStaticLibrary)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

final class GenerateAcceptanceTestCommandLineToolWithDynamicLibrary: TuistAcceptanceTestCase {
    func test_command_line_tool_with_dynamic_library() async throws {
        try await setUpFixture(.commandLineToolWithDynamicLibrary)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

final class GenerateAcceptanceTestCommandLineToolWithDynamicFramework: TuistAcceptanceTestCase {
    func test_command_line_tool_with_dynamic_framework() async throws {
        try await setUpFixture(.commandLineToolWithDynamicFramework)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

final class GenerateAcceptanceTestmacOSAppWithCopyFiles: TuistAcceptanceTestCase {
    func test_macos_app_with_copy_files() async throws {
        try await setUpFixture(.macosAppWithCopyFiles)
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
        try await withMockedDependencies {
            try await setUpFixture(.manifestWithLogs)
            try await run(GenerateCommand.self)
            XCTAssertStandardOutput(pattern: "Target name - App")
        }
    }
}

final class GenerateAcceptanceTestsProjectWithClassPrefix: TuistAcceptanceTestCase {
    func test_project_with_class_prefix() async throws {
        try await setUpFixture(.projectWithClassPrefix)
        try await run(GenerateCommand.self)

        let xcodeproj = try XcodeProj(
            pathString: xcodeprojPath.pathString
        )
        let attributes = try xcodeproj.pbxproj.rootProject()?.attributes

        XCTAssertEqual(attributes?["CLASSPREFIX"]?.stringValue, "TUIST")
    }
}

final class GenerateAcceptanceTestProjectWithFileHeaderTemplate: TuistAcceptanceTestCase {
    func test_project_with_file_header_template() async throws {
        try await setUpFixture(.projectWithFileHeaderTemplate)
        try await run(GenerateCommand.self)
        let exists = try await fileSystem.exists(
            xcodeprojPath.appending(
                components: [
                    "xcshareddata",
                    "IDETemplateMacros.plist",
                ]
            )
        )
        XCTAssertTrue(exists)
    }
}

final class GenerateAcceptanceTestProjectWithInlineFileHeaderTemplate: TuistAcceptanceTestCase {
    func test_project_with_inline_file_header_template() async throws {
        try await setUpFixture(.projectWithInlineFileHeaderTemplate)
        try await run(GenerateCommand.self)
        let exists = try await fileSystem.exists(
            xcodeprojPath.appending(
                components: [
                    "xcshareddata",
                    "IDETemplateMacros.plist",
                ]
            )
        )
        XCTAssertTrue(exists)
    }
}

final class GenerateAcceptanceTestWorkspaceWithFileHeaderTemplate: TuistAcceptanceTestCase {
    func test_workspace_with_file_header_template() async throws {
        try await setUpFixture(.workspaceWithFileHeaderTemplate)
        try await run(GenerateCommand.self)
        let exists = try await fileSystem.exists(
            workspacePath.appending(
                components: [
                    "xcshareddata",
                    "IDETemplateMacros.plist",
                ]
            )
        )
        XCTAssertTrue(exists)
    }
}

final class GenerateAcceptanceTestWorkspaceWithInlineFileHeaderTemplate: TuistAcceptanceTestCase {
    func test_workspace_with_inline_file_header_template() async throws {
        try await setUpFixture(.workspaceWithInlineFileHeaderTemplate)
        try await run(GenerateCommand.self)
        let exists = try await fileSystem.exists(
            workspacePath.appending(
                components: [
                    "xcshareddata",
                    "IDETemplateMacros.plist",
                ]
            )
        )
        XCTAssertTrue(exists)
    }
}

final class GenerateAcceptanceTestiOSAppWithFrameworkAndDisabledResources: TuistAcceptanceTestCase {
    func test_ios_app_with_framework_and_disabled_resources() async throws {
        try await setUpFixture(.iosAppWithFrameworkAndDisabledResources)
        try await run(GenerateCommand.self)
        let appExists = try await fileSystem.exists(
            fixturePath.appending(
                components: [
                    "App",
                    "Derived",
                    "Sources",
                    "TuistBundle+App.swift",
                ]
            )
        )
        XCTAssertFalse(appExists)
        let frameworkOneExists = try await fileSystem.exists(
            fixturePath.appending(
                components: [
                    "Framework1",
                    "Derived",
                    "Sources",
                    "TuistBundle+Framework1.swift",
                ]
            )
        )
        XCTAssertFalse(frameworkOneExists)
        let staticFrameworkExists = try await fileSystem.exists(
            fixturePath.appending(
                components: [
                    "StaticFramework",
                    "Derived",
                    "Sources",
                    "TuistBundle+StaticFramework.swift",
                ]
            )
        )
        XCTAssertFalse(staticFrameworkExists)
    }
}

final class GenerateAcceptanceTestmacOSAppWithExtensions: TuistAcceptanceTestCase {
    func test_macos_app_with_extensions() async throws {
        try await setUpFixture(.macosAppWithExtensions)
        let sdkPkgPath = sourceRootPath
            .appending(
                components: [
                    "fixtures",
                    "resources",
                    "WorkflowExtensionsSDK.pkg",
                ]
            )
        if try await !fileSystem.exists(
            AbsolutePath(validating: "/Library/Developer/SDKs/WorkflowExtensionSDK.sdk")
        ) {
            try System.shared.run(["sudo", "installer", "-package", sdkPkgPath.pathString, "-target", "/"])
        }

        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestiOSAppWithNoneLinkingStatusFramework: TuistAcceptanceTestCase {
    func test_ios_app_with_none_linking_status_framework() async throws {
        try await setUpFixture(.iosAppWithNoneLinkingStatusFramework)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")

        let xcodeproj = try XcodeProj(
            pathString: xcodeprojPath.pathString
        )
        let target = try XCTUnwrapTarget("App", in: xcodeproj)
        guard try target.frameworksBuildPhase()?.files?
            .contains(where: { $0.file?.nameOrPath == "MyFramework.framework" }) == false
        else {
            XCTFail("App shouldn't link MyFramework.framework")
            return
        }
        guard try target.frameworksBuildPhase()?.files?
            .contains(where: { $0.file?.nameOrPath == "ThyFramework.framework" }) == true
        else {
            XCTFail("App doesn't link ThyFramework.framework")
            return
        }
    }
}

final class GenerateAcceptanceTestiOSAppWithWeaklyLinkedFramework: TuistAcceptanceTestCase {
    func test_ios_app_with_weakly_linked_framework() async throws {
        try await setUpFixture(.iosAppWithWeaklyLinkedFramework)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")

        let xcodeproj = try XcodeProj(
            pathString: xcodeprojPath.pathString
        )
        let target = try XCTUnwrapTarget("App", in: xcodeproj)
        let frameworksBuildPhase = try target.frameworksBuildPhase()
        guard let frameworkFiles = frameworksBuildPhase?.files,
              let frameworkFile = frameworkFiles.first,
              let settings = frameworkFile.settings
        else {
            XCTFail("App target should have a linked framework with settings")
            return
        }
        let expected = ["ATTRIBUTES": BuildFileSetting.array(["Weak"])]
        XCTAssertEqualDictionaries(settings, expected)
    }
}

final class GenerateAcceptanceTestiOSAppWithCatalyst: TuistAcceptanceTestCase {
    func test_ios_app_with_catalyst() async throws {
        try await setUpFixture(.iosAppWithCatalyst)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "macos")
        try await run(BuildCommand.self, "App", "--platform", "ios")

        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-maccatalyst",
            resource: "Info.plist"
        )
    }
}

final class GenerateAcceptanceTestSPMPackage: TuistAcceptanceTestCase {
    func test_spm_package() async throws {
        try await setUpFixture(.spmPackage)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "MyPackage", "--platform", "ios")
        try await run(BuildCommand.self, "MyPackage", "--platform", "macos")
        try await run(BuildCommand.self, "MyUIKitPackage", "--platform", "ios")
        try await run(BuildCommand.self, "MyCLI")
        try await run(TestCommand.self, "--platform", "ios")
        try await run(TestCommand.self, "MyPackage", "--platform", "macos")
    }
}

final class GenerateAcceptanceTestAppWithDefaultConfiguration: TuistAcceptanceTestCase {
    func test_app_with_custom_default_configuration() async throws {
        try await setUpFixture(.appWithCustomDefaultConfiguration)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestAppWithDefaultConfigurationSettings: TuistAcceptanceTestCase {
    func test_app_with_custom_default_configuration_settings() async throws {
        try await setUpFixture(.appWithCustomDefaultConfigurationSettings)
        try await run(GenerateCommand.self)

        let xcodeproj = try XcodeProj(
            pathString: xcodeprojPath.pathString
        )

        let project = try XCTUnwrap(xcodeproj.pbxproj.projects.first)
        XCTAssertEqual(project.buildConfigurationList.defaultConfigurationName, "CustomDebug")

        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestAppWithCustomScheme: TuistAcceptanceTestCase {
    func test_app_with_custom_scheme() async throws {
        try await setUpFixture(.appWithCustomScheme)
        try await run(GenerateCommand.self)

        let xcodeproj = try XcodeProj(
            pathString: xcodeprojPath.pathString
        )

        let scheme = try XCTUnwrap(xcodeproj.sharedData?.schemes.first)
        XCTAssertEqual(scheme.name, "App")

        let buildAction = try XCTUnwrap(scheme.buildAction)
        XCTAssertFalse(buildAction.buildImplicitDependencies)

        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestGeneratediOSAppWithoutConfigManifest: TuistAcceptanceTestCase {
    func test_generated_ios_app_without_config_manifest() async throws {
        try await setUpFixture(.generatediOSAppWithoutConfigManifest)
        try await run(InstallCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GeneratediOSStaticLibraryWithStringResources: TuistAcceptanceTestCase {
    func test_generated_ios_static_library_with_string_resources() async throws {
        try await setUpFixture(.generatediOSStaticLibraryWithStringResources)
        try await run(InstallCommand.self)
        try await run(BuildCommand.self)

        let targetName = "GeneratediOSStaticLibraryWithStringResources"
        let productName = "\(targetName)_\(targetName)"
        try await XCTAssertProductWithDestinationDoesNotContainResource(
            "\(productName).bundle",
            destination: "Debug-iphonesimulator",
            resource: productName
        )
    }
}

final class GenerateAcceptanceTestsAppWithMetalOptions: TuistAcceptanceTestCase {
    func test_app_with_metal_options() async throws {
        try await setUpFixture(.appWithMetalOptions)
        try await run(GenerateCommand.self)

        try XCTAssertContainsMetalOptions(
            xcodeprojPath: xcodeprojPath,
            scheme: "CustomMetalConfig",
            apiValidation: false,
            shaderValidation: true,
            showGraphicsOverview: true,
            logGraphicsOverview: true
        )

        try XCTAssertContainsMetalOptions(
            xcodeprojPath: xcodeprojPath,
            scheme: "DefaultMetalConfig",
            apiValidation: true,
            shaderValidation: false,
            showGraphicsOverview: false,
            logGraphicsOverview: false
        )
    }
}

final class GenerateAcceptanceTestAppWithGoogleMaps: TuistAcceptanceTestCase {
    func test_app_with_google_maps() async throws {
        try await setUpFixture(.appWithGoogleMaps)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestAppWithGlobs: TuistAcceptanceTestCase {
    func test_app_with_globs() async throws {
        try await setUpFixture(.appWithGlobs)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestFrameworkWithMacroAndPluginPackages: TuistAcceptanceTestCase {
    func test_framework_with_macro_and_plugin_packages() async throws {
        try await setUpFixture(.frameworkWithMacroAndPluginPackages)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "--", "-skipPackagePluginValidation")
    }
}

final class GenerateAcceptanceTestAppWithRevenueCat: TuistAcceptanceTestCase {
    func test_app_with_revenue_cat() async throws {
        try await setUpFixture(.appWithRevenueCat)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestAppWithSwiftCMark: TuistAcceptanceTestCase {
    func test_app_with_swift_cmark() async throws {
        try await setUpFixture(.appWithSwiftCMark)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTestAppWithSPMModuleAliases: TuistAcceptanceTestCase {
    func test_app_with_spm_module_aliases() async throws {
        try await setUpFixture(.appWithSpmModuleAliases)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateAcceptanceTesAppWithLocalSPMModuleWithRemoteDependencies: TuistAcceptanceTestCase {
    func test_app_with_local_spm_module_with_remote_dependencies() async throws {
        try await setUpFixture(.appWithLocalSPMModuleWithRemoteDependencies)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)

        let workspacePackageResolved = try workspacePath
            .appending(RelativePath(validating: "xcshareddata/swiftpm/Package.resolved"))
        let fixturePackageResolved = try fixturePath.appending(RelativePath(validating: ".package.resolved"))
        let workspacePackageResolvedData = try Data(contentsOf: workspacePackageResolved.url)
        let fixturePackageResolvedData = try Data(contentsOf: fixturePackageResolved.url)
        XCTAssertEqual(workspacePackageResolvedData, fixturePackageResolvedData)
    }
}

final class GenerateAcceptanceTestAppWithNonLocalAppDependencies: TuistAcceptanceTestCase {
    func test_app_with_non_local_app_dependencies() async throws {
        try await setUpFixture(.appWithExecutableNonLocalDependencies)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "TestHost")
        try await run(BuildCommand.self, "App-Workspace")

        let xcodeproj = try XcodeProj(
            pathString: fixturePath.appending(components: "MainApp", "MainApp.xcodeproj").pathString
        )

        let target = try XCTUnwrapTarget("MainApp", in: xcodeproj)
        let buildPhases = target.buildPhases
        XCTAssertTrue(buildPhases.contains(where: { $0.name() == "Dependencies" }))

        let dependenciesBuildPhase = buildPhases.first(where: { $0.name() == "Dependencies" }) as? PBXCopyFilesBuildPhase
        let targetFileNames = dependenciesBuildPhase?.files?.compactMap { $0.file?.nameOrPath }.sorted()
        let expectedTargetFileNames = ["AppExtension.appex"]
        XCTAssertEqual(targetFileNames, expectedTargetFileNames)

        let testTarget = try XCTUnwrapTarget("MainAppTests", in: xcodeproj)
        let testBuildPhases = testTarget.buildPhases
        XCTAssertTrue(testBuildPhases.contains(where: { $0.name() == "Dependencies" }))

        let testDependenciesBuildPhase = testBuildPhases.first(where: { $0.name() == "Dependencies" }) as? PBXCopyFilesBuildPhase
        let testTargetFileNames = testDependenciesBuildPhase?.files?.compactMap { $0.file?.nameOrPath }.sorted()
        let expectedTestTargetFileNames = ["TestHost.app"]
        XCTAssertEqual(testTargetFileNames, expectedTestTargetFileNames)
    }
}

final class GenerateAcceptanceTestAppWithGeneratedSources: TuistAcceptanceTestCase {
    func test_app_with_non_local_app_dependencies() async throws {
        try await setUpFixture(.appWithGeneratedSources)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")

        let xcodeproj = try XcodeProj(
            pathString: fixturePath.appending(components: "App.xcodeproj").pathString
        )

        let target = try XCTUnwrapTarget("App", in: xcodeproj)
        let sourceFiles = try target.sourceFiles()
        let sourceFilesNames = sourceFiles.compactMap { file in
            let parent = file.parent?.path ?? ""
            let path = file.path ?? ""
            return parent + "/" + path
        }.sorted()
        let expectedPathsWithParents = [
            "$(BUILT_PRODUCTS_DIR)/GeneratedEmptyFile2.swift",
            "Generated/GeneratedEmptyFile.swift",
            "Sources/AppDelegate.swift",
        ]
        XCTAssertEqual(sourceFilesNames, expectedPathsWithParents)
    }
}

final class GenerateAcceptanceTestAppWithMacBundle: TuistAcceptanceTestCase {
    func test_app_with_mac_bundle() async throws {
        try await setUpFixture(.appWithMacBundle)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "macos")
        try await run(BuildCommand.self, "App", "--platform", "ios")

        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-maccatalyst",
            resource: "Resources/App_ProjectResourcesFramework.bundle"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-iphonesimulator",
            resource: "App_ProjectResourcesFramework.bundle"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-maccatalyst",
            resource: "Resources/ResourcesFramework_ResourcesFramework.bundle"
        )
        try await XCTAssertProductWithDestinationDoesNotContainResource(
            "App.app",
            destination: "Debug-maccatalyst",
            resource: "Resources/MacPlugin.bundle"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-maccatalyst",
            resource: "PlugIns/MacPlugin.bundle"
        )
        try await XCTAssertProductWithDestinationDoesNotContainResource(
            "App.app",
            destination: "Debug-iphonesimulator",
            resource: "MacPlugin.bundle"
        )
    }

    func test_macos_app_with_mac_bundle() async throws {
        try await setUpFixture(.appWithMacBundle)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App-macOS")

        try await XCTAssertProductWithDestinationContainsResource(
            "App_macOS.app",
            destination: "Debug",
            resource: "Resources/App_ProjectResourcesFramework.bundle"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "App_macOS.app",
            destination: "Debug",
            resource: "Resources/ResourcesFramework_ResourcesFramework.bundle"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "App_macOS.app",
            destination: "Debug",
            resource: "PlugIns/MacPlugin.bundle"
        )
        try await XCTAssertProductWithDestinationDoesNotContainResource(
            "App_macOS.app",
            destination: "Debug",
            resource: "Resources/MacPlugin.bundle"
        )
    }
}

final class GenerateAcceptanceTestAppWithSignedXCFrameworkDependencies: TuistAcceptanceTestCase {
    func test_app_with_signed_xcframework_dependencies() async throws {
        try await setUpFixture(.appWithSignedXCFrameworkDependencies)
        try await run(GenerateCommand.self)
    }

    func test_app_with_mismatching_signed_xcframework_dependencies() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.appWithSignedXCFrameworkDependenciesMismatchingSignature)
            do {
                try await run(GenerateCommand.self)
                XCTFail("Generate should have failed")
            } catch {
                XCTAssertStandardError(
                    pattern: "self signed XCFrameworks must have the format"
                )
                XCTAssertEqual(
                    (error as? FatalError)?.description,
                    "Fatal linting issues found"
                )
            }
        }
    }
}

// frameworkWithMacroAndPluginPackages

extension TuistAcceptanceTestCase {
    private func resourcePath(
        for productName: String,
        destination: String,
        resource: String
    ) async throws -> AbsolutePath {
        let productPath = try await productPath(for: productName, destination: destination)
        if let resource = try await fileSystem.glob(directory: productPath, include: ["**/\(resource)"]).collect().first {
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
        let productPath = try await productPath(
            for: product,
            destination: destination
        )

        let appClipPath = productPath.appending(components: ["AppClips", "\(appClip).app"])
        guard try await fileSystem.exists(appClipPath)
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
        let productPath = try await productPath(
            for: product,
            destination: destination
        )

        let extensionPath = productPath.appending(components: ["Plugins", "\(`extension`).appex"])
        guard try await fileSystem.exists(extensionPath)
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
        let productPath = try await productPath(
            for: product,
            destination: destination
        )

        let extensionPath = productPath.appending(components: ["Extensions", "\(`extension`).appex"])
        guard try await fileSystem.exists(extensionPath)
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
        let resourcePath = try await resourcePath(
            for: product,
            destination: destination,
            resource: resource
        )

        if try await !fileSystem.exists(resourcePath) {
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
        let productPath = try await productPath(for: product, destination: destination)
        if try await !fileSystem.glob(directory: productPath, include: ["**/\(resource)"]).collect().isEmpty {
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
        let infoPlistPath = try await resourcePath(
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
