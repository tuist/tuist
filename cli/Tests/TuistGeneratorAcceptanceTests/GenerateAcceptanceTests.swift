import Command
import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAcceptanceTesting
import TuistEnvironment
import TuistLoggerTesting
import TuistLogging
import TuistSupport
import TuistTesting
import XcodeProj

import TuistBuildCommand
import TuistGenerateCommand
import TuistTestCommand
@testable import TuistKit

struct GeneratorAcceptanceTests {
    @Test(.withFixture("generated_app_with_framework_and_tests")) func app_with_framework_and_tests() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")

        // When
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])

        // Then
        try TuistTest.expectFrameworkNotEmbedded("Framework", by: "AppExtension", inXcodeProj: xcodeprojPath)
    }

    @Test(.withFixture("generated_app_with_exponea_sdk"), .withMockedLogger()) func app_with_exponea_sdk() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)

        // When
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
    }

    @Test(.withFixture("generated_spm_dependency_with_trait_conditions"), .withMockedLogger())
    func spm_dependency_with_trait_conditions() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)

        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
    }

    @Test(.withFixture("generated_local_spm_dependency_with_assets"), .withMockedLogger())
    func local_spm_dependency_with_assets() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let workspacePath = fixtureDirectory.appending(component: "TuistSampleProject.xcworkspace")

        // When
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        try await System.shared.run([
            "/usr/bin/xcodebuild",
            "-scheme",
            "TuistSampleProject",
            "-workspace",
            workspacePath.pathString,
            "-destination",
            "generic/platform=iOS Simulator",
            "build",
        ])
    }

    @Test(
        .withFixture("generated_framework_with_environment_variables"),
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

struct GenerateAcceptanceTestiOSAppWithTests {
    @Test(.withFixture("generated_ios_app_with_tests"), .inTemporaryDirectory)
    func ios_app_with_tests() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }

    @Test(.withFixture("generated_ios_app_with_tests"), .inTemporaryDirectory)
    func focused_targets() async throws {
        let fixturePath = try fixtureDirectory()
        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)

        func generatedTargets() throws -> [String] {
            try XcodeProj(pathString: xcodeprojPath.pathString).pbxproj.nativeTargets.map(\.name).sorted()
        }

        try await run(GenerateCommand.self)
        #expect(
            try generatedTargets() == [
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
        #expect(try generatedTargets() == ["AppCore"])
    }
}

struct GenerateAcceptanceTestiOSAppWithFrameworks {
    @Test(.withFixture("generated_ios_app_with_frameworks"), .inTemporaryDirectory)
    func ios_app_with_frameworks() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await XCTAssertProductWithDestinationContainsInfoPlistKey(
            "Framework1.framework",
            destination: "Debug-iphonesimulator",
            key: "Test"
        )
    }
}

struct GenerateAcceptanceTestiOSAppWithHeaders {
    @Test(.withFixture("generated_ios_app_with_headers"), .inTemporaryDirectory)
    func ios_app_with_headers() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestInvalidWorkspaceManifestName {
    @Test(.withFixture("generated_invalid_workspace_manifest_name"), .inTemporaryDirectory)
    func invalid_workspace_manifest_name() async throws {
        let fixturePath = try fixtureDirectory()
        do {
            try await run(GenerateCommand.self)
            Issue.record("Generate command should have failed")
        } catch {
            #expect(String(describing: error) == "Manifest not found at path \(fixturePath.pathString)")
        }
    }
}

struct GenerateAcceptanceTestCacheProfilesInvalidDefault {
    @Test(.withFixture("generated_ios_app_with_cache_profiles_invalid_default"), .inTemporaryDirectory)
    func ios_app_with_cache_profiles_invalid_default() async throws {
        do {
            try await run(GenerateCommand.self)
            Issue.record("Generate command should have failed")
        } catch {
            #expect(
                String(describing: error)
                    == "Default cache profile 'missing' not found. Available profiles: .onlyExternal, .allPossible, .none, or custom profiles: development."
            )
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

struct GenerateAcceptanceTestiOSAppWithFrameworkAndResources {
    @Test(.withFixture("generated_ios_app_with_framework_and_resources"), .inTemporaryDirectory)
    func ios_app_with_framework_and_resources() async throws {
        let fixturePath = try fixtureDirectory()
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
            "StaticFramework3.framework",
            "StaticFramework4.framework",
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
            "StaticFramework3.framework",
            destination: "Debug-iphonesimulator",
            resource: "StaticFramework3Resources-tuist.png"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "StaticFramework4.framework",
            destination: "Debug-iphonesimulator",
            resource: "StaticFramework4Resources-tuist.png"
        )
        try await expectDirectoryContentEqual(
            fixturePath.appending(components: "App", "Derived", "Sources"),
            [
                "TuistBundle+App.swift",
                "TuistStrings+App.swift",
                "TuistAssets+App.swift",
                "TuistFonts+App.swift",
                "TuistPlists+App.swift",
            ]
        )
        try await expectDirectoryContentEqual(
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
        try await expectDirectoryContentEqual(
            fixturePath.appending(components: "App", "Derived", "PrivacyManifests", "App"),
            [
                "PrivacyInfo.xcprivacy",
            ]
        )
    }
}

struct GenerateAcceptanceTestiOSAppWithFrameworkXcassetsAndDefaultIntenalImports {
    @Test(.withFixture("generated_ios_app_with_framework_xcassets_and_default_internal_imports"), .inTemporaryDirectory)
    func ios_app_with_framework_xcassets_and_default_internal_imports() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestiOSAppWithOnDemandResources {
    @Test(.withFixture("generated_ios_app_with_on_demand_resources"), .inTemporaryDirectory)
    func ios_app_with_on_demand_resources() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
        let pbxprojPath = xcodeprojPath.appending(component: "project.pbxproj")
        let data = try Data(contentsOf: pbxprojPath.url)
        let pbxProj = try PBXProj(data: data)
        let attributes = try #require(pbxProj.projects.first?.attributes)
        let knownAssetTags = try #require(attributes["KnownAssetTags"]?.arrayValue)
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
        #expect(knownAssetTags == givenTags)
    }
}

struct GenerateAcceptanceTestiOSAppWithPrivacyManifest {
    @Test(.withFixture("generated_ios_app_with_privacy_manifest"), .inTemporaryDirectory)
    func ios_app_with_privacy_manifest() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await expectDirectoryContentEqual(
            fixturePath.appending(components: "Derived", "PrivacyManifests", "MyApp"),
            [
                "PrivacyInfo.xcprivacy",
            ]
        )
    }
}

struct GenerateAcceptanceTestIosAppWithCustomDevelopmentRegion {
    @Test(.withFixture("generated_ios_app_with_custom_development_region"), .inTemporaryDirectory)
    func ios_app_with_custom_development_region() async throws {
        let fixturePath = try fixtureDirectory()
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

        #expect(
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

struct GenerateAcceptanceTestiOSAppWithCustomResourceParserOptions {
    @Test(.withFixture("generated_ios_app_with_custom_resource_parser_options"), .inTemporaryDirectory)
    func ios_app_with_custom_resource_parser_options() async throws {
        let fixturePath = try fixtureDirectory()
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

        #expect(
            try FileHandler.shared.readTextFile(
                fixturePath.appending(components: "Derived", "Sources", "TuistStrings+App.swift")
            )
            .contains(
                """
                public static let evening = AppStrings.tr("Greetings", "Good/evening")
                """
            )
        )
        #expect(
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

struct GenerateAcceptanceTestiOSAppWithFrameworkLinkingStaticFramework {
    @Test(.withFixture("generated_ios_app_with_framework_linking_static_framework"), .inTemporaryDirectory)
    func ios_app_with_framework_linking_static_framework() async throws {
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

struct GenerateAcceptanceTestsiOSAppWithCustomScheme {
    @Test(.withFixture("generated_ios_app_with_custom_scheme"), .inTemporaryDirectory)
    func ios_app_with_custom_scheme() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await run(BuildCommand.self, "App-Debug")
        try await run(BuildCommand.self, "App-Release")
        try await run(BuildCommand.self, "App-Local")

        let xcodeprojPath = fixturePath.appending(components: ["App", "MainApp.xcodeproj"])

        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)

        let scheme = try #require(
            xcodeproj.sharedData?.schemes
                .filter { $0.name == "App-Debug" }
                .first
        )

        let testableTarget = try #require(
            scheme.testAction?.testables
                .filter { $0.buildableReference.blueprintName == "AppTests" }
                .first
        )

        #expect(testableTarget.parallelization == .all)

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

struct GenerateAcceptanceTestiOSAppWithLocalSwiftPackage {
    @Test(.withFixture("generated_ios_app_with_local_swift_package"), .inTemporaryDirectory)
    func ios_app_with_local_swift_package() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestiOSAppWithMultiConfigs {
    @Test(.withFixture("generated_ios_app_with_multi_configs"), .inTemporaryDirectory)
    func ios_app_with_multi_configs() async throws {
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

struct GenerateAcceptanceTestiOSAppWithIncompatibleXcode {
    @Test(.withFixture("generated_ios_app_with_incompatible_xcode"), .withMockedDependencies())
    func ios_app_with_incompatible_xcode() async throws {
        do {
            try await run(GenerateCommand.self)
            Issue.record("Generate should have failed")
        } catch {
            TuistTest.expectLogs(
                "which is not compatible with this project's Xcode version requirement of 3.2.1.",
                at: .error,
                <=
            )
            #expect(
                (error as? FatalError)?.description
                    == "Fatal linting issues found"
            )
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

struct GenerateAcceptanceTestiOSAppWithBuildVariables {
    @Test(.withFixture("generated_ios_app_with_build_variables"), .inTemporaryDirectory)
    func ios_app_with_build_variables() async throws {
        let fixturePath = try fixtureDirectory()
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

struct GenerateAcceptanceTestiOSAppWithRemoteSwiftPackage {
    @Test(.withFixture("generated_ios_app_with_remote_swift_package"), .inTemporaryDirectory)
    func ios_app_with_remote_swift_package() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestVisionOSAppWithRemoteSwiftPackage {
    @Test(.withFixture("generated_visionos_app"), .inTemporaryDirectory)
    func visionos_app() async throws {
        try await run(GenerateCommand.self)
//        TODO: Fix
//        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestiOSAppWithLocalBinarySwiftPackage {
    @Test(.withFixture("generated_ios_app_with_local_binary_swift_package"), .inTemporaryDirectory)
    func ios_app_with_local_binary_swift_package() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestiOSAppWithExtensions {
    @Test(.withFixture("generated_ios_app_with_extensions"), .inTemporaryDirectory)
    func ios_app_with_extensions() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")

        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
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

struct GenerateAcceptanceTestiOSAppWithWatchApp2 {
    @Test(.withFixture("generated_ios_app_with_watchapp2"), .inTemporaryDirectory)
    func ios_app_with_watchapp2() async throws {
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

struct GenerateAcceptanceTestInvalidManifest {
    @Test(.withFixture("generated_invalid_manifest"), .inTemporaryDirectory)
    func invalid_manifest() async throws {
        do {
            try await run(GenerateCommand.self)
            Issue.record("Generate command should have failed")
        } catch let error as FatalError {
            XCTAssertTrue(error.description.contains("error: expected ',' separator"))
        }
    }
}

struct GenerateAcceptanceTestiOSAppLarge {
    @Test(.withFixture("generated_ios_app_large"), .inTemporaryDirectory)
    func ios_app_large() async throws {
        try await run(GenerateCommand.self)
    }
}

struct GenerateAcceptanceTestiOSWorkspaceWithDependencyCycle {
    @Test(.withFixture("generated_ios_workspace_with_dependency_cycle"), .inTemporaryDirectory)
    func ios_workspace_with_dependency_cycle() async throws {
        do {
            try await run(GenerateCommand.self)
            Issue.record("Generate command should have failed")
        } catch let error as FatalError {
            XCTAssertTrue(error.description.contains("Found circular dependency between targets"))
        }
    }
}

struct GenerateAcceptanceTestiOSAppWithCoreData {
    @Test(.withFixture("generated_ios_app_with_coredata"), .inTemporaryDirectory)
    func ios_app_with_coredata() async throws {
        let fileSystem = FileSystem()
        let fixturePath = try fixtureDirectory()
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

struct GenerateAcceptanceTestiOSAppWithAppClip {
    @Test(.withFixture("generated_ios_app_with_appclip"), .inTemporaryDirectory)
    func ios_app_with_appclip() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await XCTAssertProductWithDestinationContainsAppClipWithArchitecture(
            "App.app",
            destination: "Debug-iphonesimulator",
            appClip: "AppClip1",
            architecture: "arm64"
        )
        try await XCTAssertFrameworkEmbedded("Framework", by: "AppClip1")
        try await XCTAssertProductWithDestinationContainsAppClipWithArchitecture(
            "App.app",
            destination: "Debug-iphonesimulator",
            appClip: "AppClip1",
            architecture: "arm64"
        )
        try await XCTAssertFrameworkEmbedded("Framework", by: "AppClip1")
        try await XCTAssertProductWithDestinationContainsExtension(
            "AppClip1.app",
            destination: "Debug-iphonesimulator",
            extension: "AppClip1Widgets"
        )
    }
}

struct GenerateAcceptanceTestCommandLineToolBase {
    @Test(.withFixture("generated_command_line_tool_basic"), .inTemporaryDirectory)
    func command_line_tool_basic() async throws {
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

struct GenerateAcceptanceTestGeneratedBundleWithMetalFiles {
    @Test(.withFixture("generated_bundle_with_metal_files"), .inTemporaryDirectory)
    func generated_bundle_with_metal_files() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "Bundle")
        try await XCTAssertProductWithDestinationContainsResource(
            "Bundle.bundle",
            destination: "Debug-iphonesimulator",
            resource: "default.metallib"
        )
    }
}

struct GenerateAcceptanceTestGeneratedStaticFrameworkIncludesMetalLib {
    @Test(.withFixture("generated_metallib_in_static_framework"), .inTemporaryDirectory)
    func generated_bundle_with_metal_files() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "StaticMetallibFramework")
        try await XCTAssertProductWithDestinationContainsResource(
            "StaticMetallibFramework.framework",
            destination: "Debug",
            resource: "default.metallib"
        )
    }
}

struct GenerateAcceptanceTestCommandLineToolWithStaticLibrary {
    @Test(.withFixture("generated_command_line_tool_with_static_library"), .inTemporaryDirectory)
    func command_line_tool_with_static_library() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

struct GenerateAcceptanceTestCommandLineToolWithDynamicLibrary {
    @Test(.withFixture("generated_command_line_tool_with_dynamic_library"), .inTemporaryDirectory)
    func command_line_tool_with_dynamic_library() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

struct GenerateAcceptanceTestCommandLineToolWithDynamicFramework {
    @Test(.withFixture("generated_command_line_tool_with_dynamic_framework"), .inTemporaryDirectory)
    func command_line_tool_with_dynamic_framework() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "CommandLineTool")
    }
}

struct GenerateAcceptanceTestmacOSAppWithCopyFiles {
    @Test(.withFixture("generated_macos_app_with_copy_files"), .inTemporaryDirectory)
    func macos_app_with_copy_files() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)

        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
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

struct GenerateAcceptanceTestManifestWithLogs {
    @Test(.withFixture("generated_manifest_with_logs"), .withMockedDependencies())
    func manifest_with_logs() async throws {
        try await run(GenerateCommand.self)
        TuistTest.expectLogs("Target name - App", at: .info, <=)
    }
}

struct GenerateAcceptanceTestsProjectWithClassPrefix {
    @Test(.withFixture("generated_project_with_class_prefix"), .inTemporaryDirectory)
    func project_with_class_prefix() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)

        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
        let xcodeproj = try XcodeProj(
            pathString: xcodeprojPath.pathString
        )
        let attributes = try xcodeproj.pbxproj.rootProject()?.attributes

        XCTAssertEqual(attributes?["CLASSPREFIX"]?.stringValue, "TUIST")
    }
}

struct GenerateAcceptanceTestProjectWithFileHeaderTemplate {
    @Test(.withFixture("generated_project_with_file_header_template"), .inTemporaryDirectory)
    func project_with_file_header_template() async throws {
        let fileSystem = FileSystem()
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
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

struct GenerateAcceptanceTestProjectWithInlineFileHeaderTemplate {
    @Test(.withFixture("generated_project_with_inline_file_header_template"), .inTemporaryDirectory)
    func project_with_inline_file_header_template() async throws {
        let fileSystem = FileSystem()
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
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

struct GenerateAcceptanceTestWorkspaceWithFileHeaderTemplate {
    @Test(.withFixture("generated_workspace_with_file_header_template"), .inTemporaryDirectory)
    func workspace_with_file_header_template() async throws {
        let fileSystem = FileSystem()
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        let workspacePath = try await TuistAcceptanceTest.xcworkspacePath(in: fixturePath)
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

struct GenerateAcceptanceTestWorkspaceWithInlineFileHeaderTemplate {
    @Test(.withFixture("generated_workspace_with_inline_file_header_template"), .inTemporaryDirectory)
    func workspace_with_inline_file_header_template() async throws {
        let fileSystem = FileSystem()
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        let workspacePath = try await TuistAcceptanceTest.xcworkspacePath(in: fixturePath)
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

struct GenerateAcceptanceTestiOSAppWithFrameworkAndDisabledResources {
    @Test(.withFixture("generated_ios_app_with_framework_and_disabled_resources"), .inTemporaryDirectory)
    func ios_app_with_framework_and_disabled_resources() async throws {
        let fileSystem = FileSystem()
        let fixturePath = try fixtureDirectory()
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

struct GenerateAcceptanceTestmacOSAppWithExtensions {
    @Test(.withFixture("generated_macos_app_with_extensions"), .inTemporaryDirectory)
    func macos_app_with_extensions() async throws {
        let fileSystem = FileSystem()
        let sourceRootPath = try sourceRootPath()
        let sdkPkgPath = sourceRootPath
            .appending(
                components: [
                    "examples",
                    "xcode",
                    "generated_resources",
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

struct GenerateAcceptanceTestiOSAppWithNoneLinkingStatusFramework {
    @Test(.withFixture("generated_ios_app_with_none_linking_status_framework"), .inTemporaryDirectory)
    func ios_app_with_none_linking_status_framework() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")

        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
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

struct GenerateAcceptanceTestiOSAppWithWeaklyLinkedFramework {
    @Test(.withFixture("generated_ios_app_with_weakly_linked_framework"), .inTemporaryDirectory)
    func ios_app_with_weakly_linked_framework() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")

        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
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

struct GenerateAcceptanceTestiOSAppWithCatalyst {
    @Test(.withFixture("generated_ios_app_with_catalyst"), .inTemporaryDirectory)
    func ios_app_with_catalyst() async throws {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        if osVersion.majorVersion >= 26 {
            throw Skip("Mac Catalyst destinations are not available on macOS 26+")
        }

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

struct GenerateAcceptanceTestSPMPackage {
    @Test(.withFixture("generated_spm_package"), .inTemporaryDirectory)
    func spm_package() async throws {
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

struct GenerateAcceptanceTestAppWithDefaultConfiguration {
    @Test(.withFixture("generated_app_with_custom_default_configuration"), .inTemporaryDirectory)
    func app_with_custom_default_configuration() async throws {
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestAppWithDefaultConfigurationSettings {
    @Test(.withFixture("generated_app_with_custom_default_configuration_settings"), .inTemporaryDirectory)
    func app_with_custom_default_configuration_settings() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)

        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
        let xcodeproj = try XcodeProj(
            pathString: xcodeprojPath.pathString
        )

        let project = try XCTUnwrap(xcodeproj.pbxproj.projects.first)
        XCTAssertEqual(project.buildConfigurationList.defaultConfigurationName, "CustomDebug")

        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestAppWithCustomScheme {
    @Test(.withFixture("generated_app_with_custom_scheme"), .inTemporaryDirectory)
    func app_with_custom_scheme() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)

        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
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

struct GenerateAcceptanceTestGeneratediOSAppWithoutConfigManifest {
    @Test(.withFixture("generated_ios_app_without_config_manifest"), .inTemporaryDirectory)
    func generated_ios_app_without_config_manifest() async throws {
        try await run(InstallCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GeneratediOSStaticLibraryWithStringResources {
    @Test(.withFixture("generated_ios_static_library_with_string_resources"), .inTemporaryDirectory)
    func generated_ios_static_library_with_string_resources() async throws {
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

struct GenerateAcceptanceTestsAppWithMetalOptions {
    @Test(.withFixture("generated_app_with_metal_options"), .inTemporaryDirectory)
    func app_with_metal_options() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)

        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
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

struct GenerateAcceptanceTestAppWithGoogleMaps {
    @Test(.withFixture("generated_app_with_google_maps"), .inTemporaryDirectory)
    func app_with_google_maps() async throws {
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestAppWithGlobs {
    @Test(.withFixture("generated_app_with_globs"), .inTemporaryDirectory)
    func app_with_globs() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)

        let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath)
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let allFileReferences = xcodeproj.pbxproj.fileReferences
        let allFilePaths = allFileReferences.compactMap(\.path)

        XCTAssertTrue(
            allFilePaths.contains(where: { $0.contains(".hidden.yml") }),
            "Expected .hidden.yml to be included in the project"
        )
        XCTAssertFalse(
            allFilePaths.contains(where: { $0.contains(".secret.yml") }),
            "Expected .secret.yml to be excluded from the project"
        )
    }
}

struct GenerateAcceptanceTestFrameworkWithMacroAndPluginPackages {
    @Test(.withFixture("generated_framework_with_macro_and_plugin_packages"), .inTemporaryDirectory)
    func framework_with_macro_and_plugin_packages() async throws {
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "--", "-skipPackagePluginValidation")
    }
}

struct GenerateAcceptanceTestAppWithRevenueCat {
    @Test(.withFixture("generated_app_with_revenue_cat"), .inTemporaryDirectory)
    func app_with_revenue_cat() async throws {
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestAppWithSwiftCMark {
    @Test(.withFixture("generated_app_with_swift_cmark"), .inTemporaryDirectory)
    func app_with_swift_cmark() async throws {
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTestAppWithSPMModuleAliases {
    @Test(.withFixture("generated_app_with_spm_module_aliases"), .inTemporaryDirectory)
    func app_with_spm_module_aliases() async throws {
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

struct GenerateAcceptanceTesAppWithLocalSPMModuleWithRemoteDependencies {
    @Test(.withFixture("generated_app_with_local_spm_module_with_remote_dependencies"), .inTemporaryDirectory)
    func app_with_local_spm_module_with_remote_dependencies() async throws {
        let fixturePath = try fixtureDirectory()
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)

        let workspacePath = try await TuistAcceptanceTest.xcworkspacePath(in: fixturePath)
        let workspacePackageResolved = workspacePath.appending(
            try RelativePath(validating: "xcshareddata/swiftpm/Package.resolved")
        )
        let fixturePackageResolved = fixturePath.appending(try RelativePath(validating: ".package.resolved"))
        let workspacePackageResolvedData = try Data(contentsOf: workspacePackageResolved.url)
        let fixturePackageResolvedData = try Data(contentsOf: fixturePackageResolved.url)
        XCTAssertEqual(workspacePackageResolvedData, fixturePackageResolvedData)
    }
}

struct GenerateAcceptanceTestAppWithNonLocalAppDependencies {
    @Test(.withFixture("generated_app_with_executable_non_local_dependencies"), .inTemporaryDirectory)
    func app_with_non_local_app_dependencies() async throws {
        let fixturePath = try fixtureDirectory()
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

struct GenerateAcceptanceTestAppWithGeneratedSources {
    @Test(.withFixture("generated_app_with_generated_sources"), .inTemporaryDirectory)
    func app_with_generated_sources() async throws {
        let fixturePath = try fixtureDirectory()
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

struct GenerateAcceptanceTestAppWithMacBundle {
    @Test(.withFixture("generated_app_with_mac_bundle"), .inTemporaryDirectory)
    func app_with_mac_bundle() async throws {
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "macos")
        try await run(BuildCommand.self, "App", "--platform", "ios")

        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-maccatalyst",
            resource: "Frameworks/ProjectResourcesFramework.framework"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-iphonesimulator",
            resource: "Frameworks/ProjectResourcesFramework.framework"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-maccatalyst",
            resource: "ProjectResourcesFramework.framework/Resources/greeting.txt"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-maccatalyst",
            resource: "ProjectResourcesFramework.framework/Resources/Info.plist"
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

    @Test(.withFixture("generated_app_with_mac_bundle"), .inTemporaryDirectory)
    func macos_app_with_mac_bundle() async throws {
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App-macOS")

        try await XCTAssertProductWithDestinationContainsResource(
            "App_macOS.app",
            destination: "Debug",
            resource: "Frameworks/ProjectResourcesFramework.framework"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "App_macOS.app",
            destination: "Debug",
            resource: "ProjectResourcesFramework.framework/Resources/greeting.txt"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "App_macOS.app",
            destination: "Debug",
            resource: "ProjectResourcesFramework.framework/Resources/Info.plist"
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

    /// Tests that external local Swift packages configured as dynamic frameworks
    /// compile and run without crashing when accessing Bundle.module.
    /// This is a regression test for https://github.com/tuist/tuist/issues/XXXX
    func test_app_with_external_dynamic_framework_with_resources() async throws {
        try await setUpFixture("generated_app_with_mac_bundle")

        // Modify the Tuist/Package.swift to use dynamic framework for ResourcesFramework
        let packageSwiftPath = fixturePath.appending(components: "Tuist", "Package.swift")
        let dynamicFrameworkPackageSwift = """
        // swift-tools-version: 6.0
        @preconcurrency import PackageDescription

        #if TUIST
            import struct ProjectDescription.PackageSettings

            let packageSettings = PackageSettings(
                productTypes: ["ResourcesFramework": .framework]
            )
        #endif

        let package = Package(
            name: "App",
            dependencies: [
                .package(path: "../ResourcesFramework"),
            ]
        )
        """
        try await fileSystem.writeText(
            dynamicFrameworkPackageSwift,
            at: packageSwiftPath,
            encoding: .utf8,
            options: .init([.overwrite])
        )

        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "ios")

        // Launch app on simulator to verify it doesn't crash when accessing Bundle.module
        let commandRunner = CommandRunner()
        let simulatorId = UUID().uuidString
        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "create", simulatorId, "iPhone 16 Pro"]
        ).pipedStream().awaitCompletion()

        defer {
            Task {
                try? await commandRunner.run(
                    arguments: ["/usr/bin/xcrun", "simctl", "delete", simulatorId]
                ).pipedStream().awaitCompletion()
            }
        }

        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "boot", simulatorId]
        ).pipedStream().awaitCompletion()

        let appPath = derivedDataPath
            .appending(components: ["Build", "Products", "Debug-iphonesimulator", "App.app"])

        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "install", simulatorId, appPath.pathString]
        ).pipedStream().awaitCompletion()

        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "launch", simulatorId, "dev.tuist.App"]
        ).pipedStream().awaitCompletion()

        // Wait for app to initialize and potentially crash
        try await Task.sleep(for: .seconds(2))

        // Verify the app is still running (didn't crash due to bundle accessor issue)
        let listOutput = try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "spawn", simulatorId, "launchctl", "list"]
        ).concatenatedString()

        XCTAssertTrue(
            listOutput.contains("UIKitApplication:dev.tuist.App"),
            "App should still be running. If it crashed, the bundle accessor for external dynamic frameworks with resources may be broken."
        )
    }
}

struct GenerateAcceptanceTestAppWithSignedXCFrameworkDependencies {
    @Test(.withFixture("generated_app_with_signed_xcframework_dependencies"))
    func app_with_signed_xcframework_dependencies() async throws {
        try await run(GenerateCommand.self)
    }

    @Test(.withFixture("generated_app_with_signed_xcframework_dependencies_mismatching_signature"), .withMockedDependencies())
    func app_with_mismatching_signed_xcframework_dependencies() async throws {
        do {
            try await run(GenerateCommand.self)
            Issue.record("Generate should have failed")
        } catch {
            TuistTest.expectLogs(
                "self signed XCFrameworks must have the format",
                at: .error,
                <=
            )
            #expect(
                (error as? FatalError)?.description
                    == "Fatal linting issues found"
            )
        }
    }
}

struct GenerateAcceptanceTestiOSAppWithSandboxDisabled {
    @Test(
        .withFixture("generated_ios_app_with_sandbox_disabled")
    )
    func sandbox_disabled() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        try await TuistTest.run(BuildCommand.self, ["App", "--path", fixtureDirectory.pathString])
    }

    // This test should be reenabled once https://github.com/tuist/tuist/issues/8206 is resolved
//    @Test(
//        .withFixture("generated_ios_app_with_sandbox_disabled"),
//        .withMockedEnvironment()
//    )
//    func sandbox_enabled_fails() async throws {
//        let mockEnvironment = try #require(Environment.mocked)
//        mockEnvironment.manifestLoadingVariables["TUIST_DISABLE_SANDBOX"] = "NO"
//        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
//
//        do {
//            try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
//            Issue.record("Generate should have failed with crash")
//        } catch {
//            #expect(
//                String(describing: error)
//                    .contains("The file “hosts” couldn’t be opened because you don’t have permission to view it.")
//            )
//        }
//    }
}

private enum AcceptanceTestError: Error {
    case missingProduct
    case missingResource
}

private func fixtureDirectory(sourceLocation: SourceLocation = #_sourceLocation) throws -> AbsolutePath {
    try #require(TuistTest.fixtureDirectory, sourceLocation: sourceLocation)
}

private func derivedDataPath(sourceLocation: SourceLocation = #_sourceLocation) throws -> AbsolutePath {
    try #require(FileSystem.temporaryTestDirectory, sourceLocation: sourceLocation)
}

private func sourceRootPath(sourceLocation: SourceLocation = #_sourceLocation) throws -> AbsolutePath {
    let sourceRoot = try #require(Environment.current.variables["TUIST_CONFIG_SRCROOT"], sourceLocation: sourceLocation)
    return try AbsolutePath(validating: sourceRoot)
}

private func run(
    _: GenerateCommand.Type,
    _ arguments: [String] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fixturePath = try fixtureDirectory(sourceLocation: sourceLocation)
    try await TuistTest.run(
        GenerateCommand.self,
        ["--no-open", "--path", fixturePath.pathString] + arguments
    )
}

private func run(
    _ command: GenerateCommand.Type,
    _ arguments: String...,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    try await run(command, arguments, sourceLocation: sourceLocation)
}

private func run(
    _: InstallCommand.Type,
    _ arguments: [String] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fixturePath = try fixtureDirectory(sourceLocation: sourceLocation)
    try await TuistTest.run(
        InstallCommand.self,
        ["--path", fixturePath.pathString] + arguments
    )
}

private func run(
    _ command: InstallCommand.Type,
    _ arguments: String...,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    try await run(command, arguments, sourceLocation: sourceLocation)
}

private func run(
    _: BuildCommand.Type,
    _ arguments: [String] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fixturePath = try fixtureDirectory(sourceLocation: sourceLocation)
    let derivedData = try derivedDataPath(sourceLocation: sourceLocation)
    let terminatorIndex = arguments.firstIndex(of: "--") ?? arguments.endIndex
    let regularArguments = Array(arguments.prefix(upTo: terminatorIndex))
    let passthroughArguments = Array(arguments.suffix(from: terminatorIndex))
    let assembledArguments = regularArguments + [
        "--derived-data-path",
        derivedData.pathString,
        "--path",
        fixturePath.pathString,
    ] + passthroughArguments
    try await TuistTest.run(BuildCommand.self, assembledArguments)
}

private func run(
    _ command: BuildCommand.Type,
    _ arguments: String...,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    try await run(command, arguments, sourceLocation: sourceLocation)
}

private func run(
    _: TestCommand.Type,
    _ arguments: [String] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fixturePath = try fixtureDirectory(sourceLocation: sourceLocation)
    let derivedData = try derivedDataPath(sourceLocation: sourceLocation)
    let terminatorIndex = arguments.firstIndex(of: "--") ?? arguments.endIndex
    let regularArguments = Array(arguments.prefix(upTo: terminatorIndex))
    let passthroughArguments = Array(arguments.suffix(from: terminatorIndex))
    let assembledArguments = regularArguments + [
        "--derived-data-path",
        derivedData.pathString,
        "--path",
        fixturePath.pathString,
    ] + passthroughArguments
    try await TuistTest.run(TestCommand.self, assembledArguments)
}

private func run(
    _ command: TestCommand.Type,
    _ arguments: String...,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    try await run(command, arguments, sourceLocation: sourceLocation)
}

private func productPath(
    for name: String,
    destination: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws -> AbsolutePath {
    let fileSystem = FileSystem()
    let derivedData = try derivedDataPath(sourceLocation: sourceLocation)
    let products = try await fileSystem.glob(
        directory: derivedData,
        include: ["Build/Products/\(destination)/\(name)/"]
    ).collect()
    guard let productPath = products.first else {
        Issue.record(
            "Product \(name) not found for destination \(destination)",
            sourceLocation: sourceLocation
        )
        throw AcceptanceTestError.missingProduct
    }
    return productPath
}

private func headers(for productName: String, destination: String) async throws -> [AbsolutePath] {
    let fileSystem = FileSystem()
    let productPath = try await productPath(for: productName, destination: destination)
    return try await fileSystem.glob(directory: productPath, include: ["**/*.h"]).collect()
}

private func resourcePath(
    for productName: String,
    destination: String,
    resource: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws -> AbsolutePath {
    let fileSystem = FileSystem()
    let productPath = try await productPath(
        for: productName,
        destination: destination,
        sourceLocation: sourceLocation
    )
    let matches = try await fileSystem.glob(directory: productPath, include: ["**/\(resource)"]).collect()
    guard let resourcePath = matches.first else {
        Issue.record(
            "Could not find resource \(resource) for product \(productName) and destination \(destination)",
            sourceLocation: sourceLocation
        )
        throw AcceptanceTestError.missingResource
    }
    return resourcePath
}

private func XCTAssertSchemeContainsBuildSettings(
    _ scheme: String,
    configuration: String,
    buildSettingKey: String,
    buildSettingValue: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fixturePath = try fixtureDirectory(sourceLocation: sourceLocation)
    let workspacePath = try await TuistAcceptanceTest.xcworkspacePath(in: fixturePath, sourceLocation: sourceLocation)
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

    #expect(
        buildSettings.standardOutput.contains("\(buildSettingKey) = \"\(buildSettingValue)\""),
        "Couldn't find \(buildSettingKey) = \(buildSettingValue) for scheme \(scheme) and configuration \(configuration)",
        sourceLocation: sourceLocation
    )
}

private func XCTAssertProductWithDestinationContainsAppClipWithArchitecture(
    _ product: String,
    destination: String,
    appClip: String,
    architecture: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fileSystem = FileSystem()
    let productPath = try await productPath(
        for: product,
        destination: destination,
        sourceLocation: sourceLocation
    )

    let appClipPath = productPath.appending(components: ["AppClips", "\(appClip).app"])
    guard try await fileSystem.exists(appClipPath) else {
        Issue.record(
            "App clip \(appClip) not found for product \(product) and destination \(destination)",
            sourceLocation: sourceLocation
        )
        return
    }

    let fileInfo = try await System.shared.runAndCollectOutput(
        [
            "file",
            appClipPath.appending(component: appClip).pathString,
        ]
    )
    #expect(
        fileInfo.standardOutput.contains(architecture),
        sourceLocation: sourceLocation
    )
}

private func XCTAssertProductWithDestinationContainsExtension(
    _ product: String,
    destination: String,
    extension: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fileSystem = FileSystem()
    let productPath = try await productPath(
        for: product,
        destination: destination,
        sourceLocation: sourceLocation
    )

    let extensionPath = productPath.appending(components: ["Plugins", "\(`extension`).appex"])
    #expect(
        try await fileSystem.exists(extensionPath),
        "Extension \(`extension`) not found for product \(product) and destination \(destination)",
        sourceLocation: sourceLocation
    )
}

private func XCTAssertProductWithDestinationContainsExtensionKitExtension(
    _ product: String,
    destination: String,
    extension: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fileSystem = FileSystem()
    let productPath = try await productPath(
        for: product,
        destination: destination,
        sourceLocation: sourceLocation
    )

    let extensionPath = productPath.appending(components: ["Extensions", "\(`extension`).appex"])
    #expect(
        try await fileSystem.exists(extensionPath),
        "ExtensionKit \(`extension`) not found for product \(product) and destination \(destination)",
        sourceLocation: sourceLocation
    )
}

private func XCTAssertProductWithDestinationContainsResource(
    _ product: String,
    destination: String,
    resource: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    _ = try await resourcePath(
        for: product,
        destination: destination,
        resource: resource,
        sourceLocation: sourceLocation
    )
}

private func XCTAssertProductWithDestinationDoesNotContainResource(
    _ product: String,
    destination: String,
    resource: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fileSystem = FileSystem()
    let productPath = try await productPath(for: product, destination: destination, sourceLocation: sourceLocation)
    let matches = try await fileSystem.glob(directory: productPath, include: ["**/\(resource)"]).collect()
    #expect(
        matches.isEmpty,
        "Resource \(resource) found for product \(product) and destination \(destination)",
        sourceLocation: sourceLocation
    )
}

private func XCTAssertProductWithDestinationDoesNotContainHeaders(
    _ product: String,
    destination: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let headerFiles = try await headers(for: product, destination: destination)
    #expect(
        headerFiles.isEmpty,
        "Product with name \(product) and destination \(destination) contains headers",
        sourceLocation: sourceLocation
    )
}

private func XCTAssertProductWithDestinationContainsInfoPlistKey(
    _ product: String,
    destination: String,
    key: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let infoPlistPath = try await resourcePath(
        for: product,
        destination: destination,
        resource: "Info.plist",
        sourceLocation: sourceLocation
    )
    let output = try await System.shared.runAndCollectOutput(
        [
            "/usr/libexec/PlistBuddy",
            "-c",
            "print :\(key)",
            infoPlistPath.pathString,
        ]
    )

    #expect(
        output.standardOutput.isEmpty == false,
        "Key \(key) not found in the \(product) Info.plist",
        sourceLocation: sourceLocation
    )
}

private func XCTAssertFrameworkEmbedded(
    _ framework: String,
    by targetName: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fixturePath = try fixtureDirectory(sourceLocation: sourceLocation)
    let xcodeprojPath = try await TuistAcceptanceTest.xcodeprojPath(in: fixturePath, sourceLocation: sourceLocation)
    try await TuistAcceptanceTest.expectFrameworkEmbedded(
        framework,
        by: targetName,
        xcodeprojPath: xcodeprojPath,
        sourceLocation: sourceLocation
    )
}

private func XCTAssertContainsSimulatedLocation(
    xcodeprojPath: AbsolutePath,
    scheme: String,
    testTarget: String,
    simulatedLocation: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)

    let scheme = try #require(
        xcodeproj.sharedData?.schemes
            .filter { $0.name == scheme }
            .first,
        sourceLocation: sourceLocation
    )

    let testableTarget = try #require(
        scheme.testAction?.testables
            .filter { $0.buildableReference.blueprintName == testTarget }
            .first,
        sourceLocation: sourceLocation
    )

    #expect(
        testableTarget.locationScenarioReference?.identifier.contains(simulatedLocation) == true,
        "The '\(testableTarget)' testable target doesn't have simulated location set.",
        sourceLocation: sourceLocation
    )
}

private func XCTAssertContainsMetalOptions(
    xcodeprojPath: AbsolutePath,
    scheme: String,
    apiValidation: Bool,
    shaderValidation: Bool,
    showGraphicsOverview: Bool,
    logGraphicsOverview: Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)

    guard let scheme = xcodeproj.sharedData?.schemes
        .filter({ $0.name == scheme })
        .first
    else {
        Issue.record(
            "The '\(scheme)' scheme doesn't exist.",
            sourceLocation: sourceLocation
        )
        return
    }

    guard let launchAction = scheme.launchAction
    else {
        Issue.record(
            "The '\(scheme)' doesn't have launch action.",
            sourceLocation: sourceLocation
        )
        return
    }

    #expect(
        launchAction.disableGPUValidationMode == !apiValidation,
        "The launch action of '\(scheme)' doesn't have 'API Validation' set.",
        sourceLocation: sourceLocation
    )
    #expect(
        launchAction.enableGPUShaderValidationMode == shaderValidation,
        "The launch action of '\(scheme)' doesn't have 'Shader Validation' set.",
        sourceLocation: sourceLocation
    )
    #expect(
        launchAction.showGraphicsOverview == showGraphicsOverview,
        "The launch action of '\(scheme)' doesn't have 'Show Graphics Overview' set.",
        sourceLocation: sourceLocation
    )
    #expect(
        launchAction.logGraphicsOverview == logGraphicsOverview,
        "The launch action of '\(scheme)' doesn't have 'Log Graphics Overview' set.",
        sourceLocation: sourceLocation
    )
}

private func XCTAssertTrue(
    _ expression: @autoclosure () throws -> Bool,
    _ message: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) rethrows {
    #expect(try expression(), message, sourceLocation: sourceLocation)
}

private func XCTAssertFalse(
    _ expression: @autoclosure () throws -> Bool,
    _ message: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) rethrows {
    #expect(try expression() == false, message, sourceLocation: sourceLocation)
}

private func XCTAssertEqual<T: Equatable>(
    _ first: @autoclosure () throws -> T,
    _ second: @autoclosure () throws -> T,
    _ message: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) rethrows {
    #expect(try first() == second(), message, sourceLocation: sourceLocation)
}

private func XCTAssertEqualDictionaries<T: Hashable>(
    _ first: [T: Any],
    _ second: [T: Any],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let firstDictionary = NSDictionary(dictionary: first)
    let secondDictionary = NSDictionary(dictionary: second)
    #expect(firstDictionary.isEqual(secondDictionary), sourceLocation: sourceLocation)
}

private func XCTFail(
    _ message: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    Issue.record(message, sourceLocation: sourceLocation)
}

private func XCTUnwrap<T>(
    _ value: T?,
    _ message: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> T {
    if !message.isEmpty, value == nil {
        Issue.record(message, sourceLocation: sourceLocation)
    }
    return try #require(value, sourceLocation: sourceLocation)
}

private func XCTUnwrapTarget(
    _ targetName: String,
    in xcodeproj: XcodeProj,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> PBXTarget {
    try await TuistAcceptanceTest.requireTarget(targetName, in: xcodeproj, sourceLocation: sourceLocation)
}
