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

    @Test(.inTemporaryDirectory, arguments: ["verified", "unrelated", "ambiguous"])
    func verifiesObservedSymlinkAliasesBeforeRecordingThem(status: String) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let producer = try await target(at: root.appending(component: "producer"))
        let consumer = try await target(at: root.appending(component: "consumer"))
        let unrelated = try await target(at: root.appending(component: "unrelated"))
        let aliasRoot = root.appending(component: "compiler-checkout")
        try FileManager.default.createSymbolicLink(
            at: aliasRoot.url,
            withDestinationURL: (status == "unrelated" ? unrelated : producer).project.sourceRootPath.url
        )
        let debugPath = aliasRoot.appending(components: "Feature", "Feature.swift").pathString
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: producer)
        var debugSources: Set<String> = [debugPath]
        if status == "ambiguous" {
            debugSources.insert(try #require(metadata.sourcePaths["Feature/Feature.swift"]))
        }
        if status == "unrelated" {
            await #expect(throws: (any Error).self) {
                try await metadata.recording(debugSources: debugSources, fileSystem: FileSystem())
            }
            return
        }
        if status == "verified" {
            #expect(throws: (any Error).self) { try metadata.recording(debugSources: debugSources) }
        }
        let recorded = try await metadata.recording(debugSources: debugSources, fileSystem: FileSystem())
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(recorded, at: artifact)
        try await FileSystem().remove(aliasRoot)
        try await FileSystem().remove(producer.project.sourceRootPath)
        let mappings = try #require(await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: consumer))
        #expect(Set(mappings.map(\.original.pathString)) == debugSources)
        #expect(Set(mappings.map(\.current)) == [consumer.project.sourceRootPath.appending(
            components: "Feature",
            "Feature.swift"
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
    func recordsMultipleVerifiedCompilerSpellingsOfOneSource() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let target = try await target(at: root)
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: target)
        let recorded = try metadata.recording(
            debugSources: ["/^one/Feature/Feature.swift", "/^two/Feature/Feature.swift"],
            prefixMappings: [["/^one": root.pathString, "/^two": root.pathString]]
        )
        #expect(recorded.debugPaths["Feature/Feature.swift"] == ["/^one/Feature/Feature.swift", "/^two/Feature/Feature.swift"])
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

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func doesNotFollowMetadataSymlinksOutsideTheArtifact(parentDirectory: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let target = try await target(at: root.appending(component: "checkout"))
        let source = target.project.sourceRootPath.appending(components: "Feature", "Feature.swift")
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: target)
            .recording(debugSources: [source.pathString])
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(metadata, at: artifact)
        let outside = root.appending(components: "outside", CachedModuleDebuggingMetadata.fileName)
        try await FileSystem().makeDirectory(at: outside.parentDirectory)
        try await FileSystem().writeAsJSON(metadata, at: outside)
        let path = artifact.appending(components: "macos-arm64", CachedModuleDebuggingMetadata.fileName)
        let link = parentDirectory ? path.parentDirectory : path
        try await FileSystem().remove(link)
        try FileManager.default.createSymbolicLink(
            at: link.url, withDestinationURL: parentDirectory ? outside.parentDirectory.url : outside.url
        )
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

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func verifiesGeneratedSourcesBeforeTheirSideEffectsRun(stale: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let producer = try await target(at: root.appending(component: "producer"))
        let consumer = try await target(at: root.appending(component: "consumer"))
        let content = Data("public let generated = 42\n".utf8)
        let checksum = try ContentHasher().hash(content)
        func generated(_ base: GraphTarget) -> GraphTarget {
            var target = base.target
            target.sources = [SourceFile(
                path: base.path.appending(components: "Derived", "nested", "Generated.swift"), contentHash: checksum
            )]
            return GraphTarget(path: base.path, target: target, project: base.project)
        }
        let original = generated(producer)
        let current = generated(consumer)
        let before = try await CachedModuleDebuggingMetadata.capture(target: original)
        let producerSource = try #require(original.target.sources.first?.path)
        try await FileSystem().makeDirectory(at: producerSource.parentDirectory)
        try content.write(to: producerSource.url)
        #expect(try await CachedModuleDebuggingMetadata.capture(target: original, validateGeneratedSources: true) == before)
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(before.recording(debugSources: [producerSource.pathString]), at: artifact)
        let consumerSource = try #require(current.target.sources.first?.path)
        if stale {
            try await FileSystem().makeDirectory(at: consumerSource.parentDirectory)
            try await FileSystem().writeText("stale", at: consumerSource)
        }
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: current) == [DebuggerSourceMapping(
            original: producerSource, current: consumerSource
        )])
        try await FileSystem().writeText("changed during build", at: producerSource)
        #expect(try await CachedModuleDebuggingMetadata.capture(target: original, validateGeneratedSources: true) != before)
    }

    @Test(.inTemporaryDirectory)
    func placeholderGeneratedOutputsCannotBypassSourceVerification() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let base = try await target(at: root)
        let source = try #require(base.target.sources.first?.path)
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: base).recording(debugSources: [source.pathString])
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(metadata, at: artifact)
        var generated = SourceFile(path: root.appending(component: "Generated.swift"), contentHash: "path-fingerprint")
        let legacyJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(generated)) as? [String: Any])
        #expect(legacyJSON["contentHashIsPlaceholder"] == nil)
        let legacy = try JSONDecoder().decode(SourceFile.self, from: JSONEncoder().encode(generated))
        #expect(legacy.contentHashIsPlaceholder == nil)
        generated.contentHashIsPlaceholder = true
        let decoded = try JSONDecoder().decode(SourceFile.self, from: JSONEncoder().encode(generated))
        #expect(decoded.contentHashIsPlaceholder == true)
        var target = base.target
        target.sources.append(generated)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(
            at: artifact, for: GraphTarget(path: root, target: target, project: base.project)
        ) == nil)
    }

    @Test(.inTemporaryDirectory)
    func capturesBuildableFoldersAndSiblingInclusions() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let base = try await target(at: root)
        let source = try #require(base.target.sources.first?.path)
        let siblingSource = root.appending(component: "Shared.swift")
        try await FileSystem().writeText("public let shared = 1", at: siblingSource)
        var target = base.target
        target.sources = []
        target.buildableFolders = [.init(path: source.parentDirectory, exceptions: [], resolvedFiles: [
            .init(path: source, compilerFlags: nil), .init(path: root.appending(component: ".DS_Store"), compilerFlags: nil),
        ])]
        let sibling = Target.test(name: "Sibling", buildableFolders: [.init(
            path: root, exceptions: [.init(
                excluded: [],
                compilerFlags: [:],
                publicHeaders: [],
                privateHeaders: [],
                target: "Feature",
                included: [siblingSource]
            )], resolvedFiles: []
        )])
        var project = base.project
        project.targets["Feature"] = target
        project.targets["Sibling"] = sibling
        let graphTarget = GraphTarget(path: root, target: target, project: project)
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: graphTarget)
        #expect(Set(metadata.sources.keys) == ["Feature/Feature.swift", "Shared.swift"])
        let artifact = root.appending(component: "Feature.xcframework")
        let empty = CachedModuleDebuggingMetadata(
            version: metadata.version, moduleName: metadata.moduleName, sourceRoot: root,
            sources: [:], sourcePaths: [:], debugPaths: [:]
        )
        try await write(empty, at: artifact)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: graphTarget) == nil)
    }

    @Test(.inTemporaryDirectory)
    func doesNotReadUnobservedDeclaredSourcesDuringAdmission() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let base = try await target(at: root)
        let source = try #require(base.target.sources.first?.path)
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: base).recording(debugSources: [source.pathString])
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(metadata, at: artifact)
        var target = base.target
        target.sources.append(SourceFile(path: root.appending(component: "NotCompiledForThisSDK.swift")))
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(
            at: artifact, for: GraphTarget(path: root, target: target, project: base.project)
        ) != nil)
    }

    @Test(.inTemporaryDirectory)
    func rejectsTwoDeclaredFilesClaimingTheSameCompilerAlias() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let base = try await target(at: root)
        let other = root.appending(components: "Other", "Feature.swift")
        try await FileSystem().makeDirectory(at: other.parentDirectory)
        try await FileSystem().writeText("public let other = 1", at: other)
        var target = base.target
        target.sources.append(SourceFile(path: other))
        let metadata = try await CachedModuleDebuggingMetadata.capture(
            target: GraphTarget(path: root, target: target, project: base.project)
        )
        #expect(throws: (any Error).self) {
            try metadata.recording(debugSources: ["/^shared/Feature.swift"], prefixMappings: [
                ["/^shared": root.appending(component: "Feature").pathString], ["/^shared": other.parentDirectory.pathString],
            ])
        }
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
