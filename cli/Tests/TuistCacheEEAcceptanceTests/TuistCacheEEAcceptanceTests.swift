import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAcceptanceTesting
import TuistCacheCommand
import TuistEnvironment
import TuistEnvironmentTesting
import TuistGenerateCommand
import TuistLoggerTesting
import TuistNooraTesting
import TuistServer
import TuistSupport
import TuistTestCommand
import TuistTesting
import XcodeProj

@testable import TuistCacheEE
@testable import TuistKit

struct TuistCacheEEAcceptanceTests {
    @Test(
        .disabled("Requires simulator and SPM install"),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_framework_with_native_swift_macro")
    ) func framework_with_native_swift_macro() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let mockedEnvironment = try #require(Environment.mocked)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])

        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString, "Framework"])

        let xcodeProj =
            try XcodeProj(path: .init(fixtureDirectory.appending(component: "FrameworkWithSwiftMacro.xcodeproj").pathString))

        let frameworkTarget = try #require(xcodeProj.pbxproj.targets(named: "Framework").first)
        let configurationList = try #require(frameworkTarget.buildConfigurationList)
        #expect(configurationList.buildConfigurations.isEmpty == false)
        for buildConfiguration in configurationList.buildConfigurations {
            let otherSwiftFlags = try #require(buildConfiguration.buildSettings["OTHER_SWIFT_FLAGS"]?.arrayValue)
            #expect(otherSwiftFlags.contains(where: { $0.contains(mockedEnvironment.cacheDirectory.pathString) }) == true)
        }
    }

    @Test(
        .disabled("Requires SPM install"),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_external_dependencies_filtered_out")
    ) func generated_ios_app_with_external_dependencies_filtered_out() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])

        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )
    }

    @Test(
        .disabled("Requires SPM install"),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_frameworks_keeping_target_sources")
    ) func generated_ios_app_with_frameworks_keeping_target_sources() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "MainApp.xcodeproj")
        let xcworkspacePath = fixtureDirectory.appending(component: "MainApp.xcworkspace")
        let fileSystem = FileSystem()
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])

        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString, "Framework1"])

        try TuistTest.expectContainsTarget("App", inXcodeProj: xcodeprojPath)

        try TuistTest.expectLinked("Framework1.framework", by: "App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework2-iOS.xcframework", by: "App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework3.xcframework", by: "App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework4.xcframework", by: "App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework5.xcframework", by: "App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework3.xcframework", by: "Framework2-iOS", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework4.xcframework", by: "Framework2-iOS", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework5.xcframework", by: "Framework2-iOS", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework4.xcframework", by: "Framework3", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework5.xcframework", by: "Framework3", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework5.xcframework", by: "Framework4", inXcodeProj: xcodeprojPath)

        let schemes = try await fileSystem.glob(directory: xcworkspacePath, include: ["xcshareddata/xcschemes/*.xcscheme"])
            .collect()
        let cachedSchemePath = try #require(schemes.first(where: { $0.basename == "MainApp-Cached.xcscheme" }))
        let cachedScheme = try XCScheme(pathString: cachedSchemePath.pathString)
        let schemeTargets = cachedScheme.buildAction?.buildActionEntries.map(\.buildableReference.blueprintName).sorted()
        #expect(schemeTargets == [
            "Framework2-iOS",
            "Framework2-macOS",
            "Framework3",
            "Framework4",
            "Framework5",
            "GoogleUtilities-NSData",
        ])

        let arguments = [
            "-scheme", "App",
            "-destination", "generic/platform=iOS Simulator",
            "-workspace", xcworkspacePath.pathString,
            "-derivedDataPath", temporaryDirectory.pathString,
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
    }

    @Test(
        .disabled("Requires simulator"),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withTestingSimulator("iPhone 17"),
        .withFixture("generated_feature_tests_with_cached_library_and_googlemaps")
    ) func generated_feature_tests_with_cached_library_and_googlemaps() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let simulator = try #require(Simulator.testing)
        let xcodeprojPath = fixtureDirectory.appending(components: "Feature", "Feature.xcodeproj")

        try await TuistTest.run(
            CacheCommand.self,
            ["Library", "--path", fixtureDirectory.pathString]
        )

        try await TuistTest.run(
            TestCommand.self,
            [
                "Feature",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
                "--device",
                simulator.name,
                "--",
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )

        try TuistAcceptanceTest.expectXCFrameworkLinked(
            "Library",
            by: "Feature",
            xcodeprojPath: xcodeprojPath
        )
        try TuistAcceptanceTest.expectXCFrameworkLinked(
            "Library",
            by: "FeatureTests",
            xcodeprojPath: xcodeprojPath
        )
        try TuistAcceptanceTest.expectXCFrameworkNotLinked(
            "GoogleMaps",
            by: "Feature",
            xcodeprojPath: xcodeprojPath
        )
        try TuistAcceptanceTest.expectXCFrameworkNotLinked(
            "GoogleMapsBase",
            by: "Feature",
            xcodeprojPath: xcodeprojPath
        )
        try TuistAcceptanceTest.expectXCFrameworkNotLinked(
            "GoogleMapsCore",
            by: "Feature",
            xcodeprojPath: xcodeprojPath
        )
    }

    @Test(
        .disabled("Requires SPM install"),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_catalyst")
    ) func ios_app_with_catalyst_caches_mac_catalyst_slice() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let mockedEnvironment = try #require(Environment.mocked)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])

        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString, "App"])

        let xcworkspacePath = fixtureDirectory.appending(component: "App.xcworkspace")
        let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")
        try TuistAcceptanceTest.expectXCFrameworkLinked("Framework", by: "App", xcodeprojPath: xcodeprojPath)

        let arguments = [
            "-workspace", xcworkspacePath.pathString,
            "-scheme", "App",
            "-destination", "generic/platform=macOS,variant=Mac Catalyst",
            "-derivedDataPath", temporaryDirectory.pathString,
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
    }

    @Test(
        .disabled("Slow"),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_appintents_framework")
    ) func ios_app_with_appintents_framework_caches_metadata() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let mockedEnvironment = try #require(Environment.mocked)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        let metadataFiles = try await fileSystem.glob(
            directory: mockedEnvironment.cacheDirectory,
            include: ["**/*.xcframework/**/*.framework/Metadata.appintents"]
        ).collect()
        #expect(!metadataFiles.isEmpty, "Metadata.appintents should be embedded in the cached xcframework slices")

        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString, "App"])

        let xcworkspacePath = fixtureDirectory.appending(component: "AppIntentsApp.xcworkspace")
        let arguments = [
            "-workspace", xcworkspacePath.pathString,
            "-scheme", "App",
            "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", temporaryDirectory.pathString,
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
    }

    @Test(
        .disabled("Slow"),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH", "JAVA_HOME", "GRADLE_HOME"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_foreign_build_dependency")
    ) func generated_ios_app_with_foreign_build_dependency() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "ForeignBuildApp.xcodeproj")

        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        try await TuistTest.run(
            GenerateCommand.self,
            ["--no-open", "--path", fixtureDirectory.pathString, "App"]
        )

        try TuistTest.expectContainsTarget("App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework1.xcframework", by: "App", inXcodeProj: xcodeprojPath)
    }

    // Regression test for https://github.com/tuist/tuist/pull/9946: passing a positional target
    // whose dependency tree includes internal targets caused the cache command to short-circuit
    // with "All cacheable targets are already cached" because the dependencies were excluded
    // from hashing, which in turn made the root target itself fail the transitive-hashability
    // check in GraphContentHasher.
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_cache_profiles")
    ) func cache_warm_with_positional_target_hashes_transitive_dependencies() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])

        try await TuistTest.run(
            CacheCommand.self,
            [
                "--path", fixtureDirectory.pathString,
                "--cache-profile", "all-possible",
                "--generate-only",
                "NonCacheableModule",
            ]
        )

        TuistTest.expectLogs("Targets to be cached: ExpensiveModule, NonCacheableModule")
        TuistTest.doesntExpectLogs("All cacheable targets are already cached")
    }
}
