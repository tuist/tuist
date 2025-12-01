import Foundation
import Mockable
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistLoader
@testable import TuistTesting

final class TargetManifestMapperErrorTests: TuistUnitTestCase {
    func test_description_when_nonSpecificGeneratedResource() {
        // Given
        let path = try! AbsolutePath(validating: "/path/to/A")
        let subject = TargetManifestMapperError.nonSpecificGeneratedResource(targetName: "Target", generatedSource: path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(
            got,
            "Generated source files must be explicit. The target Target has a generated source file at /path/to/A that has a glob pattern."
        )
    }
}

final class TargetManifestMapperTests: TuistUnitTestCase {
    func test_from() async throws {
        // Given
        let rootDirectory = try temporaryPath()
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
            manifestDirectory: try temporaryPath(),
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
                ]))],
            ),
            generatorPaths: generatorPaths,
            externalDependencies: [:],
            fileSystem: fileSystem,
            contentHasher: mockContentHasher,
            type: .local
        )

        // Then
        XCTAssertEqual(got.sources.count, 2)
        XCTAssertEqual(got.sources[0].path, secondSourceFile)
        XCTAssertNil(got.sources[0].contentHash) // Regular files don't have contentHash
        XCTAssertEqual(got.sources[1].path, scriptOutputFile)
        XCTAssertEqual(got.sources[1].contentHash, "mock-hash") // Generated files should have contentHash from mock
        XCTAssertEqual(
            got.buildableFolders,
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

    func test_errorThrown_when_generatedSourceIsGlobPattern() async throws {
        // Given
        let rootDirectory = try temporaryPath()
        let sourcePath = rootDirectory.appending(component: "Scripts").appending(component: "**")

        // When
        let mockContentHasher = MockContentHashing()

        await XCTAssertThrowsSpecific(
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
                    manifestDirectory: try temporaryPath(),
                    rootDirectory: rootDirectory
                ),
                externalDependencies: [:],
                fileSystem: fileSystem,
                contentHasher: mockContentHasher,
                type: .local
            ),
            TargetManifestMapperError.nonSpecificGeneratedResource(targetName: "Target", generatedSource: sourcePath)
        )
    }

    func test_generatedSourceFiles_haveContentHash() async throws {
        // Given
        let rootDirectory = try temporaryPath()
        let generatedFilePath = "Scripts/GeneratedFile.swift"
        let generatorPaths = GeneratorPaths(
            manifestDirectory: try temporaryPath(),
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
        XCTAssertEqual(target.sources.map(\.path), [resolvedPath])
        XCTAssertEqual(target.sources.map(\.contentHash), [expectedHash])

        verify(mockContentHasher)
            .hash(Parameter<String>.value("generated-file-Scripts/GeneratedFile.swift"))
            .called(1)
    }
}
