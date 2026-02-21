import FileSystem
import FileSystemTesting
import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistLoader
@testable import TuistTesting

struct BuildableFolderExceptionManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func from_withLiteralPaths() async throws {
        let buildableFolder = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.touch(buildableFolder.appending(component: "Excluded.swift"))
        try await fileSystem.touch(buildableFolder.appending(component: "WithFlags.swift"))
        try await fileSystem.touch(buildableFolder.appending(component: "Public.h"))
        try await fileSystem.touch(buildableFolder.appending(component: "Private.h"))
        try await fileSystem.makeDirectory(at: buildableFolder.appending(component: "Resources"))
        try await fileSystem.touch(buildableFolder.appending(components: "Resources", "ios_only.mp4"))

        let got = try await XcodeGraph.BuildableFolderException.from(
            manifest: ProjectDescription.BuildableFolderException
                .exception(
                    excluded: ["Excluded.swift"],
                    compilerFlags: ["WithFlags.swift": "-flag"],
                    publicHeaders: ["Public.h"],
                    privateHeaders: ["Private.h"],
                    platformFilters: ["Resources/ios_only.mp4": [.ios]]
                ),
            buildableFolder: buildableFolder,
            fileSystem: fileSystem
        )

        #expect(got.excluded == [buildableFolder.appending(components: ["Excluded.swift"])])
        #expect(got.compilerFlags == [buildableFolder.appending(components: ["WithFlags.swift"]): "-flag"])
        #expect(got.publicHeaders == [buildableFolder.appending(components: ["Public.h"])])
        #expect(got.privateHeaders == [buildableFolder.appending(components: ["Private.h"])])
        #expect(
            got.platformFilters == [
                buildableFolder.appending(components: ["Resources", "ios_only.mp4"]):
                    XcodeGraph.PlatformCondition.when([.ios])!,
            ]
        )
    }

    @Test(.inTemporaryDirectory) func from_withGlobPattern() async throws {
        let buildableFolder = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(at: buildableFolder.appending(component: "Sources"))
        try await fileSystem.touch(buildableFolder.appending(components: "Sources", "File.swift"))
        try await fileSystem.touch(buildableFolder.appending(components: "Sources", "data.json"))
        try await fileSystem.touch(buildableFolder.appending(components: "Sources", "config.json"))

        let got = try await XcodeGraph.BuildableFolderException.from(
            manifest: ProjectDescription.BuildableFolderException
                .exception(excluded: ["**/*.json"]),
            buildableFolder: buildableFolder,
            fileSystem: fileSystem
        )

        let excludedSet = Set(got.excluded)
        #expect(excludedSet.contains(buildableFolder.appending(components: "Sources", "data.json")))
        #expect(excludedSet.contains(buildableFolder.appending(components: "Sources", "config.json")))
        #expect(!excludedSet.contains(buildableFolder.appending(components: "Sources", "File.swift")))
    }
}
