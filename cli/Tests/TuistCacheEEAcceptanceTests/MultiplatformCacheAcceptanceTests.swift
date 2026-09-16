import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAcceptanceTesting
import TuistCache
import TuistCacheCommand
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistGenerateCommand
import TuistLoggerTesting
import TuistNooraTesting
import TuistTesting

@testable import TuistKit

struct MultiplatformCacheAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_workspace_with_multiplatform_cache")
    ) func rewrittenWorkspaceReusesCombinedXCFrameworks() async throws {
        let fixture = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let cache = try CacheDirectoriesProvider().cacheDirectory(for: .binaries)
        try await TuistTest.run(InstallCommand.self, ["--path", fixture.pathString])
        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixture.pathString, "--no-upload", "--cache-profile", "only-external", "PhoneConsumer", "MacConsumer"]
        )
        let warmed = Set(try await fileSystem.glob(directory: cache, include: ["*/*.xcframework"]).collect())
        #expect(warmed.count == 2)
        let warmedBlobs = try await fileSystem.glob(directory: cache, include: ["*/blob"]).collect()
        #expect(!warmedBlobs.isEmpty)
        let actionDirectory = CacheDirectoriesProvider().cacheDirectory().appending(component: "BinaryCacheActions")
        #expect(try await fileSystem.glob(directory: actionDirectory, include: ["*/result.pb"]).collect().count == 6)
        let workspace = fixture.appending(component: "Workspace.swift")
        try Data("import ProjectDescription\nlet workspace = Workspace(name: \"PlatformCache\", projects: [\"Phone\"])\n".utf8)
            .write(to: workspace.url)
        try await TuistTest.run(GenerateCommand.self, ["--path", fixture.pathString, "--no-open", "PhoneConsumer"])
        let workspaceContents = try String(
            contentsOf: fixture.appending(components: ["PlatformCache.xcworkspace", "contents.xcworkspacedata"]).url,
            encoding: .utf8
        )
        #expect(!workspaceContents.contains("Mac.xcodeproj"))
        let project = fixture.appending(components: ["Phone", "Phone.xcodeproj"])
        try TuistTest.expectLinked("Shared.xcframework", by: "PhoneConsumer", inXcodeProj: project)
        try TuistTest.expectLinked("Leaf.xcframework", by: "PhoneConsumer", inXcodeProj: project)
        let after = try await fileSystem.glob(directory: cache, include: ["*/*.xcframework"]).collect()
        let narrowed = Set(after).subtracting(warmed)
        #expect(narrowed.count == 2)
        for artifact in narrowed {
            #expect(try await BinaryCacheArtifact.coverage(at: artifact).keys.sorted() == ["ios-device", "ios-simulator"])
        }
        #expect(Set(try await fileSystem.glob(directory: cache, include: ["*/blob"]).collect()) == Set(warmedBlobs))
        try await TuistTest.run(GenerateCommand.self, ["--path", fixture.pathString, "--no-open", "PhoneConsumer"])
        #expect(Set(try await fileSystem.glob(directory: cache, include: ["*/*.xcframework"]).collect()) == Set(after))
        for destination in ["generic/platform=iOS", "generic/platform=iOS Simulator"] {
            try await TuistTest.run(XcodeBuildBuildCommand.self, [
                "-workspace", fixture.appending(component: "PlatformCache.xcworkspace").pathString,
                "-scheme", "PhoneConsumer", "-destination", destination,
                "-derivedDataPath", temporaryDirectory.appending(component: "build").pathString,
                "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
            ])
        }
    }
}
