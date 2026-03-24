import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistLoader
@testable import TuistTesting

struct TargetManifestMapperErrorTests {
    @Test func description_when_nonSpecificGeneratedResource() throws {
        // Given
        let path = try AbsolutePath(validating: "/path/to/A")
        let subject = TargetManifestMapperError.nonSpecificGeneratedResource(targetName: "Target", generatedSource: path)

        // When
        let got = subject.description

        // Then
        #expect(
            got ==
                "Generated source files must be explicit. The target Target has a generated source file at /path/to/A that has a glob pattern."
        )
    }
}

struct TargetManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func test_from() async throws {
        // Given
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let sourcesDirectory = rootDirectory.appending(component: "Sources")
        let buildableSourcesDirectory = rootDirectory.appending(component: "BuildableSources")
        let buildableSourceFile = buildableSourcesDirectory.appending(component: "buildable.swift")
        let buildableExcludedFile = buildableSourcesDirectory.appending(component: "excluded.swift")
        let buildableFlagsFile = buildableSourcesDirectory.appending(component: "flags.swift")
        let firstDirectory = sourcesDirectory.appending(component: "first")
        let secondDirectory = firstDirectory.appending(component: "second")
        let secondSourceFile = secondDirectory.appending(component: "second.swift")
        let secondExcludedSourceFile = secondDirectory.appending(component: "second-exclude.swift")
        try await fileSystem.makeDirectory(at: sourcesDirectory)
        try await fileSystem.makeDirectory(at: buildableSourcesDirectory)
        try await fileSystem.makeDirectory(at: firstDirectory)
        try await fileSystem.makeDirectory(at: secondDirectory)
        try await fileSystem.touch(secondSourceFile)
        try await fileSystem.touch(secondExcludedSourceFile)
        try await fileSystem.touch(buildableSourceFile)
        try await fileSystem.touch(buildableExcludedFile)
        try await fileSystem.touch(buildableFlagsFile)
        let scriptOutputFile = rootDirectory.appending(component: "Scripts").appending(component: "file.swift")
        let generatorPaths = GeneratorPaths(
            manifestDirectory: rootDirectory,
            rootDirectory: rootDirectory
        )

        // When
        let mockContentHasher = MockContentHashing()
        given(mockContentHasher)
            .hash(Parameter<String>.any)
            .willReturn("mock-hash")

        let got = try await XcodeGraph.Target.from(
            manifest: .test(
                sources: .sourceFilesList(
                    globs: [
                        .glob(
                            .relativeToRoot("Sources/**"),
                            excluding: [
                                .relativeToRoot("Sources/**/*exclude.swift"),
                            ]
                        ),
                        .generated("Scripts/file.swift"),
                    ]
                ),
                resources: .resources([]),
                scripts: [.test(
                    order: .pre,
                    outputPaths: ["Scripts/file.swift"]
                )],
                buildableFolders: [.folder("BuildableSources", exceptions: .exceptions([
                    .exception(
                        excluded: ["excluded.swift"],
                        compilerFlags: ["flags.swift": "-print-stats"],
                        publicHeaders: ["headers/public.h"],
                        privateHeaders: ["headers/private.h"]
                    ),
                ]))]
            ),
            generatorPaths: generatorPaths,
            externalDependencies: [:],
            fileSystem: fileSystem,
            contentHasher: mockContentHasher,
            type: .local
        )

        // Then
        #expect(got.sources.count == 2)
        #expect(got.sources[0].path == secondSourceFile)
        #expect(got.sources[0].contentHash == nil)
        #expect(got.sources[1].path == scriptOutputFile)
        #expect(got.sources[1].contentHash == "mock-hash")
        #expect(
            got.buildableFolders ==
                [
                    BuildableFolder(
                        path: buildableSourcesDirectory,
                        exceptions: [
                            BuildableFolderException(excluded: [
                                try generatorPaths.resolve(path: "BuildableSources/excluded.swift"),
                            ], compilerFlags: [
                                try generatorPaths.resolve(path: "BuildableSources/flags.swift"): "-print-stats",
                            ], publicHeaders: [
                                try generatorPaths.resolve(path: "BuildableSources/headers/public.h"),
                            ], privateHeaders: [
                                try generatorPaths.resolve(path: "BuildableSources/headers/private.h"),
                            ]),
                        ],
                        resolvedFiles: [
                            BuildableFolderFile(path: buildableFlagsFile, compilerFlags: "-print-stats"),
                            BuildableFolderFile(path: buildableSourceFile, compilerFlags: nil),
                        ]
                    ),
                ]
        )
    }

    @Test(.inTemporaryDirectory) func errorThrown_when_generatedSourceIsGlobPattern() async throws {
        // Given
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let sourcePath = rootDirectory.appending(component: "Scripts").appending(component: "**")

        // When
        let mockContentHasher = MockContentHashing()

        await #expect(throws: TargetManifestMapperError.nonSpecificGeneratedResource(
            targetName: "Target",
            generatedSource: sourcePath
        )) {
            try await XcodeGraph.Target.from(
                manifest: .test(
                    name: "Target",
                    sources: .sourceFilesList(
                        globs: [
                            .generated("Scripts/**"),
                        ]
                    ),
                    resources: .resources([]),
                    scripts: [.test(
                        order: .pre,
                        outputPaths: ["Scripts/file.swift"]
                    )]
                ),
                generatorPaths: GeneratorPaths(
                    manifestDirectory: rootDirectory,
                    rootDirectory: rootDirectory
                ),
                externalDependencies: [:],
                fileSystem: fileSystem,
                contentHasher: mockContentHasher,
                type: .local
            )
        }
    }

    @Test(.inTemporaryDirectory) func generatedSourceFiles_haveContentHash() async throws {
        // Given
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let generatedFilePath = "Scripts/GeneratedFile.swift"
        let generatorPaths = GeneratorPaths(
            manifestDirectory: rootDirectory,
            rootDirectory: rootDirectory
        )

        // When
        let mockContentHasher = MockContentHashing()
        let expectedHash = "mock-generated-hash"
        let resolvedPath = try generatorPaths.resolve(path: .relativeToRoot(generatedFilePath))

        given(mockContentHasher)
            .hash(Parameter<String>.any)
            .willReturn(expectedHash)

        let target = try await XcodeGraph.Target.from(
            manifest: .test(
                name: "TestTarget",
                sources: .sourceFilesList(
                    globs: [
                        .generated(.relativeToRoot(generatedFilePath)),
                    ]
                ),
                resources: .resources([]),
                scripts: [.test(
                    order: .pre,
                    outputPaths: [.relativeToRoot(generatedFilePath)]
                )]
            ),
            generatorPaths: generatorPaths,
            externalDependencies: [:],
            fileSystem: fileSystem,
            contentHasher: mockContentHasher,
            type: .local
        )

        // Then
        #expect(target.sources.map(\.path) == [resolvedPath])
        #expect(target.sources.map(\.contentHash) == [expectedHash])

        verify(mockContentHasher)
            .hash(Parameter<String>.value("generated-file-Scripts/GeneratedFile.swift"))
            .called(1)
    }
}
