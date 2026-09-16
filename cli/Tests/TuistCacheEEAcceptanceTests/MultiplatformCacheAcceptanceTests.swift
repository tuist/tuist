import FileSystem
import FileSystemTesting
import Foundation
import Path
import SwiftProtobuf
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
import TuistREAPI
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
        #expect(try await fileSystem.glob(directory: cache, include: ["action-*/result.pb"]).collect().count == 6)
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
            #expect(try await XCFrameworkCoverageService().coverage(at: artifact).keys.sorted() == [
                "ios-device",
                "ios-simulator",
            ])
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
        try await TuistTest.run(CleanCommand.self, ["binaries", "--path", fixture.pathString])
        #expect(try await fileSystem.glob(directory: cache, include: ["action-*/result.pb"]).collect().isEmpty)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_workspace_with_multiplatform_cache")
    ) func packageResourceBundleUsesExactREAPIAction() async throws {
        let fixture = try #require(TuistTest.fixtureDirectory)
        let fileSystem = FileSystem()
        let consumer = fixture.appending(components: ["Mac", "Project.swift"])
        let consumerManifest = try String(contentsOf: consumer.url, encoding: .utf8)
            .replacingOccurrences(of: "product: .commandLineTool", with: "product: .app")
        try Data(consumerManifest.utf8).write(to: consumer.url)
        let resources = fixture.appending(components: ["LocalPackage", "Sources", "Shared", "Resources"])
        try await fileSystem.makeDirectory(at: resources)
        try Data("cached-resource".utf8).write(to: resources.appending(component: "value.txt").url)
        let manifest = fixture.appending(components: ["LocalPackage", "Package.swift"])
        let contents = try String(contentsOf: manifest.url, encoding: .utf8)
            .replacingOccurrences(
                of: "dependencies: [\"Leaf\"]",
                with: "dependencies: [\"Leaf\"], resources: [.process(\"Resources\")]"
            )
        try Data(contents.utf8).write(to: manifest.url)
        try await TuistTest.run(InstallCommand.self, ["--path", fixture.pathString])
        try await TuistTest.run(CacheCommand.self, [
            "--path", fixture.pathString, "--no-upload", "--cache-profile", "only-external", "PhoneConsumer", "MacConsumer",
        ])
        let provider = CacheDirectoriesProvider()
        let actions = try provider.cacheDirectory(for: .binaries)
        let results = try await fileSystem.glob(directory: actions, include: ["action-*/result.pb"]).collect()
        let exact = try results.map { try REAPI.ActionResult(serializedBytes: Data(contentsOf: $0.url)) }
            .filter { $0.outputDirectories.first?.path == "outputs" }
        #expect(exact.count == 1)
        let cache = try provider.cacheDirectory(for: .binaries)
        let bundles = try await fileSystem.glob(directory: cache, include: ["*/*.bundle"]).collect()
        #expect(bundles.count == 1)
        let original = try #require(bundles.first)
        try await fileSystem.remove(original)
        try await TuistTest.run(GenerateCommand.self, ["--path", fixture.pathString, "--no-open", "MacConsumer"])
        let restoredFiles = try await fileSystem.glob(directory: original, include: ["**/value.txt"]).collect()
        let restoredResource = try #require(restoredFiles.first)
        #expect(try Data(contentsOf: restoredResource.url) == Data("cached-resource".utf8))
        let project = fixture.appending(components: ["Mac", "Mac.xcodeproj", "project.pbxproj"])
        #expect(try String(contentsOf: project.url, encoding: .utf8).contains(original.basename))
    }
}
