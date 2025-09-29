import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAcceptanceTesting
import TuistServer
import TuistSupport
import TuistTesting
import XcodeProj

@testable import TuistCacheEE

struct TuistCacheEEAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_external_dependencies_filtered_out")
    ) func generated_ios_app_with_external_dependencies_filtered_out() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)

        // When: Cache the binaries
        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_frameworks_keeping_target_sources")
    ) func generated_ios_app_with_frameworks_keeping_target_sources() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "MainApp.xcodeproj")
        let xcworkspacePath = fixtureDirectory.appending(component: "MainApp.xcworkspace")
        let fileSystem = FileSystem()
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])

        // When: Cache the binaries
        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // When: Generate with a focuson the App
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString, "Framework1"])

        // Then
        // The app doesn't get tree-shaked
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

        // Then: Schemes
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

        // Then: Builds
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
}
