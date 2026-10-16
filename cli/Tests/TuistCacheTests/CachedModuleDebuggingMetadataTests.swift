import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistCache

struct CachedModuleDebuggingMetadataTests {
    @Test(.inTemporaryDirectory, arguments: [false, true])
    func restoresSourcePathsWithoutProducerInputs(mapped: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let producer = try await target(at: root.appending(component: "producer"))
        let consumer = try await target(at: root.appending(component: "consumer"))
        let source = producer.project.sourceRootPath.appending(components: "Feature", "Feature.swift")
        let debugPath = mapped ? "/^root/Feature/Feature.swift" : source.pathString
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: producer)
            .recording(debugSources: [debugPath], prefixMappings: [["/^root": producer.project.sourceRootPath.pathString]])
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(metadata, at: artifact)
        try await FileSystem().remove(producer.project.sourceRootPath)

        let mappings = try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: consumer)
        #expect(mappings == [DebuggerSourceMapping(
            original: try AbsolutePath(validating: debugPath),
            current: consumer.project.sourceRootPath.appending(components: "Feature", "Feature.swift")
        )])
    }

    @Test(.inTemporaryDirectory)
    func rejectsChangedSources() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let producer = try await target(at: root.appending(component: "producer"))
        let consumer = try await target(at: root.appending(component: "consumer"), contents: "public let value = 99\n")
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: producer)
            .recording(
                debugSources: ["/^root/Feature/Feature.swift"],
                prefixMappings: [["/^root": producer.project.sourceRootPath.pathString]]
            )
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(metadata, at: artifact)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: consumer) == nil)
    }

    @Test(.inTemporaryDirectory)
    func requiresMetadataInEverySlice() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let target = try await target(at: root.appending(component: "checkout"))
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: target)
            .recording(
                debugSources: ["/^root/Feature/Feature.swift"],
                prefixMappings: [["/^root": target.project.sourceRootPath.pathString]]
            )
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(metadata, at: artifact)
        try await FileSystem().remove(artifact.appending(components: "ios-arm64", CachedModuleDebuggingMetadata.fileName))
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: target) == nil)
    }

    @Test(.inTemporaryDirectory)
    func doesNotGuessAmbiguousDebugSources() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let target = try await target(at: root)
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: target)
        #expect(throws: (any Error).self) {
            try metadata.recording(
                debugSources: ["/^one/Feature/Feature.swift", "/^two/Feature/Feature.swift"],
                prefixMappings: [["/^one": root.pathString, "/^two": root.pathString]]
            )
        }
    }

    @Test(.inTemporaryDirectory)
    func doesNotInferMappingsFromMatchingFilenameSuffixes() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let target = try await target(at: root)
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: target)
        #expect(throws: (any Error).self) {
            try metadata.recording(debugSources: ["/^unrelated/Feature/Feature.swift"])
        }
    }

    @Test(.inTemporaryDirectory)
    func rejectsMissingDebugInformation() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let target = try await target(at: root)
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: target)
        #expect(throws: (any Error).self) {
            try metadata.recording(debugSources: [])
        }
    }

    @Test(.inTemporaryDirectory)
    func rejectsUnsupportedOrOversizedMetadataBeforeUsingItsMappings() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let target = try await target(at: root.appending(component: "checkout"))
        let source = target.project.sourceRootPath.appending(components: "Feature", "Feature.swift")
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: target)
            .recording(debugSources: [source.pathString])
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(metadata, at: artifact)
        let path = artifact.appending(components: "macos-arm64", CachedModuleDebuggingMetadata.fileName)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path.url)) as? [String: Any])
        json["version"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: path.url)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: target) == nil)
        try Data(repeating: 0, count: 4 * 1024 * 1024 + 1).write(to: path.url)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: target) == nil)
    }

    @Test(.inTemporaryDirectory)
    func doesNotFollowMetadataSymlinksOutsideTheArtifact() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let target = try await target(at: root.appending(component: "checkout"))
        let source = target.project.sourceRootPath.appending(components: "Feature", "Feature.swift")
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: target)
            .recording(debugSources: [source.pathString])
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(metadata, at: artifact)
        let outside = root.appending(component: "outside.json")
        try await FileSystem().writeAsJSON(metadata, at: outside)
        let path = artifact.appending(components: "macos-arm64", CachedModuleDebuggingMetadata.fileName)
        try await FileSystem().remove(path)
        try FileManager.default.createSymbolicLink(at: path.url, withDestinationURL: outside.url)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: target) == nil)
    }

    @Test(.inTemporaryDirectory)
    func cancellationDoesNotTurnIntoAnUnsupportedArtifact() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let target = try await target(at: root.appending(component: "checkout"))
        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await CachedModuleDebuggingMetadata.sourceMappings(
                at: root.appending(component: "missing.xcframework"),
                for: target
            )
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func target(at root: AbsolutePath, contents: String = "public let value = 42\n") async throws -> GraphTarget {
        let source = root.appending(components: "Feature", "Feature.swift")
        try await FileSystem().makeDirectory(at: source.parentDirectory)
        try await FileSystem().writeText(contents, at: source)
        let target = Target.test(name: "Feature", product: .framework, sources: [SourceFile(path: source)])
        let project = Project.test(path: root, sourceRootPath: root, targets: [target])
        return GraphTarget(path: root, target: target, project: project)
    }

    private func write(_ metadata: CachedModuleDebuggingMetadata, at artifact: AbsolutePath) async throws {
        let identifiers = ["macos-arm64", "ios-arm64"]
        let libraries: [[String: Any]] = identifiers.map {
            [
                "LibraryIdentifier": $0,
                "LibraryPath": "Feature.framework",
                "SupportedPlatform": $0.hasPrefix("macos") ? "macos" : "ios",
                "SupportedArchitectures": ["arm64"],
            ]
        }
        for identifier in identifiers {
            let slice = artifact.appending(component: identifier)
            try await FileSystem().makeDirectory(at: slice)
            try await FileSystem().writeAsJSON(metadata, at: slice.appending(component: CachedModuleDebuggingMetadata.fileName))
        }
        let plist: [String: Any] = [
            "AvailableLibraries": libraries,
            "CFBundlePackageType": "XFWK",
            "XCFrameworkFormatVersion": "1.0",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: artifact.appending(component: "Info.plist").url)
    }
}
