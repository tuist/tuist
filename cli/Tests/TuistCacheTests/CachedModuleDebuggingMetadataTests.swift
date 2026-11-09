import FileSystem
import FileSystemTesting
import Foundation
import Path
import TestCoverageAttribution
import Testing
import TuistCore
import XcodeGraph
@testable import TuistCache

@Suite(.coverageAttribution)
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

    @Test(
        .inTemporaryDirectory,
        arguments: [
            "empty", "debug", "stripped", "data", "bss", "common", "mixed",
            "fat-mixed", "fat-empty", "fat64-mixed", "fat64-empty", "bitcode",
        ]
    )
    func staticArchivesRequireDebugSourcesUnlessEveryMemberIsEmpty(kind: String) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let source = root.appending(component: "anchor.c")
        let contents = switch kind {
        case "data": "int value = 42;"
        case "bss", "common": "int value;"
        case "debug", "stripped", "bitcode": "int value(void) { return 42; }"
        default: "// intentionally empty"
        }
        try await fileSystem.writeText(contents, at: source)
        let object = root.appending(component: "anchor.o")
        _ = try runTool([
            "clang", "-g", "-arch", "arm64", "-c", source.pathString, "-o", object.pathString,
        ] + (["stripped", "data", "bss", "common", "bitcode"].contains(kind) ? ["-g0"] : [])
            + (kind == "bitcode" ? ["-emit-llvm"] : []) + (kind == "common" ? ["-fcommon"] : []))
        let binary = root.appending(component: "libFeature.a")
        _ = try runTool(["libtool", "-static", "-o", binary.pathString, object.pathString])
        if kind == "mixed" || kind.hasPrefix("fat") {
            let other = root.appending(component: "other.c")
            let otherObject = root.appending(component: "other.o")
            try await fileSystem.writeText(kind.hasSuffix("empty") ? "// empty" : "int hidden(void) { return 7; }", at: other)
            _ = try runTool([
                "clang", "-g0", "-arch", kind.hasPrefix("fat") ? "x86_64" : "arm64",
                "-c", other.pathString, "-o", otherObject.pathString,
            ])
            if kind == "mixed" {
                _ = try runTool(["libtool", "-static", "-o", binary.pathString, object.pathString, otherObject.pathString])
            } else {
                let otherArchive = root.appending(component: "other.a")
                _ = try runTool(["libtool", "-static", "-o", otherArchive.pathString, otherObject.pathString])
                _ = try runTool([
                    "lipo", "-create", binary.pathString, otherArchive.pathString, "-output", binary.pathString,
                ] + (kind.hasPrefix("fat64") ? ["-fat64"] : []))
            }
        }
        let target = Target.test(name: "Feature", product: .staticFramework, sources: [SourceFile(path: source)])
        let graphTarget = GraphTarget(
            path: root,
            target: target,
            project: .test(path: root, sourceRootPath: root, targets: [target])
        )
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: graphTarget)
        let output = kind == "bitcode" ? "" : try runTool(["dwarfdump", "--show-sources", binary.pathString])
        let debugSources = Set(output.split(whereSeparator: \.isNewline).map(String.init).filter { $0.hasPrefix("/") })
        if ["empty", "fat-empty", "fat64-empty", "debug"].contains(kind) {
            let recorded = try await metadata.recording(debugSources: debugSources, staticBinary: binary, fileSystem: fileSystem)
            let artifact = root.appending(component: "Feature.xcframework")
            try await write(recorded, at: artifact)
            let mappings = try #require(await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: graphTarget))
            #expect(mappings.count == (kind == "debug" ? 1 : 0))
        } else {
            await #expect(throws: (any Error).self) {
                try await metadata.recording(debugSources: debugSources, staticBinary: binary, fileSystem: fileSystem)
            }
        }
    }

    @Test(
        .inTemporaryDirectory,
        arguments: [
            "objc", "simulator-objc", "version-c", "version-objc", "excluded", "extra-code", "extra-data", "extra-bss",
            "common", "wrong-module", "extra-version-symbol", "version-code", "wrong-version-number",
            "fat-mixed", "fat64-mixed", "unknown-member", "same-filename",
        ]
    )
    func staticMetadataOnlyProductsStillRejectUnexpectedStorage(kind: String) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let source = root.appending(component: kind == "version-c" ? "dummy.c" : "dummy.m")
        let contents = switch kind {
        case "extra-code", "excluded": "int hidden(void) { return 37; }"
        case "extra-data": "int hidden = 37;"
        case "extra-bss", "common": "int hidden;"
        default: "// intentionally empty"
        }
        try await fileSystem.writeText(contents, at: source)
        let object = root.appending(component: "dummy.o")
        var objects: [String] = []
        if kind != "excluded" {
            _ = try runTool([
                "clang", "-g", "-arch", "arm64", "-c", source.pathString, "-o", object.pathString,
            ] + (kind.hasPrefix("extra-") || kind == "common" ? ["-g0"] : [])
                + (kind == "common" ? ["-fcommon"] : [])
                + (kind == "simulator-objc" ? ["-target", "arm64-apple-ios16.0-simulator"] : []))
            objects.append(object.pathString)
        }
        if !["objc", "simulator-objc"].contains(kind) {
            let version = root.appending(component: "Feature_vers.c")
            let module = kind == "wrong-module" ? "Unrelated" : "Feature"
            // Xcode's generated source contains exactly these two constants, even for a code-less target.
            let extra = switch kind {
            case "extra-version-symbol": "const int hidden = 19;"
            case "version-code": "int hidden(void) { return 19; }"
            default: ""
            }
            try await fileSystem.writeText("""
            extern const unsigned char \(module)VersionString[];
            extern const double \(module)VersionNumber;
            const unsigned char \(module)VersionString[] __attribute__((used)) =
                "@(#)PROGRAM:\(module)  PROJECT:Example-3.2\\n";
            const double \(module)VersionNumber __attribute__((used)) = \(kind == "wrong-version-number" ? "9.7" : "3.2");
            \(extra)
            """, at: version)
            let versionObject = root.appending(component: "Feature_vers.o")
            _ = try runTool(["clang", "-g", "-arch", "arm64", "-c", version.pathString, "-o", versionObject.pathString])
            objects.append(versionObject.pathString)
        }
        let binary = root.appending(component: "libFeature.a")
        _ = try runTool(["libtool", "-static", "-o", binary.pathString] + objects)
        let target = Target.test(name: "Feature", product: .staticFramework, sources: [SourceFile(path: source)])
        let graphTarget = GraphTarget(
            path: root, target: target, project: .test(path: root, sourceRootPath: root, targets: [target])
        )
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: graphTarget)
        let output = try runTool(["dwarfdump", "--show-sources", binary.pathString])
        var debugSources = Set(output.split(whereSeparator: \.isNewline).map(String.init).filter { $0.hasPrefix("/") })
        if kind.hasPrefix("fat") {
            let other = root.appending(component: "other.c")
            try await fileSystem.writeText("int hidden(void) { return 91; }", at: other)
            let otherObject = root.appending(component: "other.o")
            _ = try runTool(["clang", "-g0", "-arch", "x86_64", "-c", other.pathString, "-o", otherObject.pathString])
            let otherArchive = root.appending(component: "other.a")
            _ = try runTool(["libtool", "-static", "-o", otherArchive.pathString, otherObject.pathString])
            _ = try runTool([
                "lipo", "-create", binary.pathString, otherArchive.pathString, "-output", binary.pathString,
            ] + (kind == "fat64-mixed" ? ["-fat64"] : []))
        } else if kind == "unknown-member" {
            let unknown = root.appending(component: "unknown.o")
            try await fileSystem.writeText("not a Mach-O object", at: unknown)
            // Apple's ranlib silently drops unknown members when rebuilding the index.
            _ = try runTool(["ar", "-qS", binary.pathString, unknown.pathString])
            #expect(try runTool(["ar", "-t", binary.pathString]).contains("unknown.o"))
        } else if kind == "same-filename" {
            debugSources.insert("/^unrelated/dummy.m")
        }
        if ["objc", "simulator-objc", "version-c", "version-objc", "excluded"].contains(kind) {
            let recorded = try await metadata.recording(debugSources: debugSources, staticBinary: binary, fileSystem: fileSystem)
            #expect(recorded.debugPaths.isEmpty)
            let artifact = root.appending(component: "Feature.xcframework")
            try await write(recorded, at: artifact)
            #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: graphTarget) == [])
        } else {
            await #expect(throws: (any Error).self) {
                try await metadata.recording(debugSources: debugSources, staticBinary: binary, fileSystem: fileSystem)
            }
        }
    }

    @Test(.inTemporaryDirectory)
    func admitsSourcesWithoutLinkedCodeWithNothingToRelocate() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let producer = try await target(at: root.appending(component: "producer"))
        let consumer = try await target(at: root.appending(component: "consumer"))
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: producer)
        let debugSources: Set<String> = ["/^spm/checkouts/Dependency/Dependency.swift"]
        #expect(throws: (any Error).self) { try metadata.recording(debugSources: debugSources) }
        let recorded = try metadata.recording(debugSources: debugSources, linkedDebugSymbols: true)
        #expect(recorded.debugPaths.isEmpty)
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(recorded, at: artifact)
        try await FileSystem().remove(producer.project.sourceRootPath)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: consumer) == [])
        var target = consumer.target
        target.sources.append(SourceFile(path: consumer.project.sourceRootPath.appending(component: "Unrecorded.swift")))
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(
            at: artifact, for: GraphTarget(path: consumer.path, target: target, project: consumer.project)
        ) == nil)
    }

    @Test(.inTemporaryDirectory)
    func linkedSymbolsStillRejectUnmappedSpellingsOfDeclaredSources() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: target(at: root))
        #expect(throws: (any Error).self) {
            try metadata.recording(debugSources: ["/^unrelated/Feature/Feature.swift"], linkedDebugSymbols: true)
        }
    }

    @Test(.inTemporaryDirectory)
    func attributesSymlinkedHeaderSpellingsToTheRealFile() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        func withHeaders(at root: AbsolutePath) async throws -> GraphTarget {
            let base = try await target(at: root)
            let header = root.appending(components: "Sources", "pb.h")
            try await FileSystem().makeDirectory(at: header.parentDirectory)
            try await FileSystem().writeText("int pb(void);\n", at: header)
            let link = root.appending(components: "Headers", "nanopb", "pb.h")
            try await FileSystem().makeDirectory(at: link.parentDirectory)
            try FileManager.default.createSymbolicLink(atPath: link.pathString, withDestinationPath: "../../Sources/pb.h")
            var target = base.target
            target.headers = Headers(public: [link], private: [], project: [header])
            var project = base.project
            project.targets[target.name] = target
            return GraphTarget(path: root, target: target, project: project)
        }
        let producer = try await withHeaders(at: root.appending(component: "producer"))
        let consumer = try await withHeaders(at: root.appending(component: "consumer"))
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: producer)
        let header = try #require(metadata.sourcePaths["Sources/pb.h"])
        let linked = producer.project.sourceRootPath.appending(components: "Headers", "nanopb", "pb.h").pathString
        let recorded = try await metadata.recording(debugSources: [header, linked], fileSystem: FileSystem())
        #expect(recorded.debugPaths == ["Sources/pb.h": [header, linked]])
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(recorded, at: artifact)
        try await FileSystem().remove(producer.project.sourceRootPath)
        let mappings = try #require(await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: consumer))
        #expect(Set(mappings.map(\.original.pathString)) == [header, linked])
        #expect(Set(mappings.map(\.current)) == [consumer.project.sourceRootPath.appending(components: "Sources", "pb.h")])
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

    /// Package targets such as svgnative declare every header under their root (thousands, for a vendored boost) while
    /// DWARF observes only the few that contribute code. Admission revalidates only observed files, so publishing the
    /// others only grows the slice metadata, past its size limit for such targets.
    @Test(.inTemporaryDirectory)
    func publishesOnlyObservedSources() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let producer = try await target(at: root.appending(component: "producer"))
        let consumer = try await target(at: root.appending(component: "consumer"))
        func withHeaders(_ base: GraphTarget) async throws -> GraphTarget {
            let directory = base.project.sourceRootPath.appending(components: "include", "vendor")
            try await FileSystem().makeDirectory(at: directory)
            let headers = (0 ..< 3).map { directory.appending(component: "Header\($0).hpp") }
            for header in headers {
                try await FileSystem().writeText("#pragma once\n", at: header)
            }
            var target = base.target
            target.headers = .test(public: headers)
            return GraphTarget(path: base.path, target: target, project: base.project)
        }
        let producerWithHeaders = try await withHeaders(producer)
        let consumerWithHeaders = try await withHeaders(consumer)
        let metadata = try await CachedModuleDebuggingMetadata.capture(target: producerWithHeaders)
        #expect(metadata.sources.count == 4)
        let debugPath = "/^root/Feature/Feature.swift"
        let recorded = try metadata.recording(
            debugSources: [debugPath],
            prefixMappings: [["/^root": producer.project.sourceRootPath.pathString]]
        )
        #expect(Set(recorded.sources.keys) == ["Feature/Feature.swift"])
        #expect(Set(recorded.sourcePaths.keys) == ["Feature/Feature.swift"])
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(recorded, at: artifact)
        try await FileSystem().remove(producer.project.sourceRootPath)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: consumerWithHeaders) == [
            DebuggerSourceMapping(
                original: try AbsolutePath(validating: debugPath),
                current: consumer.project.sourceRootPath.appending(components: "Feature", "Feature.swift")
            ),
        ])
    }

    /// A header-only package target such as svgnative's boost compiles a source without code, so DWARF observes nothing
    /// and admission compares the declared set instead. Its thousands of headers are not compiled on their own, so only
    /// the compiled sources are recorded and compared.
    @Test(.inTemporaryDirectory)
    func comparesCompiledSourcesOfTargetsWithoutObservedSources() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        func target(at directory: AbsolutePath, headers: Int, extraSource: Bool = false) async throws -> GraphTarget {
            let base = try await self.target(at: directory)
            let include = directory.appending(components: "include", "vendor")
            try await FileSystem().makeDirectory(at: include)
            let paths = (0 ..< headers).map { include.appending(component: "Header\($0).hpp") }
            for path in paths {
                try await FileSystem().writeText("#pragma once\n", at: path)
            }
            var target = base.target
            target.headers = .test(public: paths)
            if extraSource {
                let source = directory.appending(components: "Feature", "Extra.cpp")
                try await FileSystem().writeText("int extra() { return 1; }\n", at: source)
                target.sources.append(SourceFile(path: source))
            }
            return GraphTarget(path: base.path, target: target, project: base.project)
        }
        let producer = try await target(at: root.appending(component: "producer"), headers: 3)
        let recorded = try await CachedModuleDebuggingMetadata.capture(target: producer)
            .recording(debugSources: ["/^spm/checkouts/Dependency/Dependency.swift"], linkedDebugSymbols: true)
        #expect(recorded.debugPaths.isEmpty)
        #expect(Set(recorded.sources.keys) == ["Feature/Feature.swift"])
        let artifact = root.appending(component: "Feature.xcframework")
        try await write(recorded, at: artifact)
        try await FileSystem().remove(producer.project.sourceRootPath)

        let sameSources = try await target(at: root.appending(component: "consumer"), headers: 5)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: sameSources) == [])
        let extraSource = try await target(at: root.appending(component: "other"), headers: 3, extraSource: true)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: extraSource) == nil)

        // Earlier CLIs recorded headers too. Their artifacts keep their hash, so warming never replaces them.
        let legacyProducer = try await target(at: root.appending(component: "legacy-producer"), headers: 3)
        let captured = try await CachedModuleDebuggingMetadata.capture(target: legacyProducer)
        let legacy = CachedModuleDebuggingMetadata(
            version: captured.version, moduleName: captured.moduleName, sourceRoot: captured.sourceRoot,
            sources: captured.sources, sourcePaths: captured.sourcePaths, debugPaths: [:]
        )
        let legacyArtifact = root.appending(component: "Legacy.xcframework")
        try await write(legacy, at: legacyArtifact)
        let legacyConsumer = try await target(at: root.appending(component: "legacy-consumer"), headers: 3)
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: legacyArtifact, for: legacyConsumer) == [])
        #expect(try await CachedModuleDebuggingMetadata.sourceMappings(at: legacyArtifact, for: sameSources) == nil)
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

    private func runTool(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "Command failed: \(arguments)")
        return String(decoding: data, as: UTF8.self)
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
