import Foundation
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
        let buildableSources = rootDirectory.appending(component: "BuildableSources")
        let buildableSourceFile = buildableSources.appending(component: "buildable.swift")
        let firstDirectory = sourcesDirectory.appending(component: "first")
        let secondDirectory = firstDirectory.appending(component: "second")
        let secondSourceFile = secondDirectory.appending(component: "second.swift")
        let secondExcludedSourceFile = secondDirectory.appending(component: "second-exclude.swift")
        try await fileSystem.makeDirectory(at: sourcesDirectory)
        try await fileSystem.makeDirectory(at: buildableSources)
        try await fileSystem.makeDirectory(at: firstDirectory)
        try await fileSystem.makeDirectory(at: secondDirectory)
        try await fileSystem.touch(secondSourceFile)
        try await fileSystem.touch(secondExcludedSourceFile)
        try await fileSystem.touch(buildableSourceFile)
        let scriptOutputFile = rootDirectory.appending(component: "Scripts").appending(component: "file.swift")

        // When
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
                buildableFolders: [.folder("BuildableSources")],
            ),
            generatorPaths: GeneratorPaths(
                manifestDirectory: try temporaryPath(),
                rootDirectory: rootDirectory
            ),
            externalDependencies: [:],
            fileSystem: fileSystem,
            type: .local
        )

        // Then
        XCTAssertEqual(
            got.sources,
            [
                SourceFile(path: secondSourceFile),
                SourceFile(path: scriptOutputFile),
            ]
        )
        XCTAssertEqual(
            got.buildableFolders,
            [
                BuildableFolder(path: buildableSources),
            ]
        )
    }

    func test_errorThrown_when_generatedSourceIsGlobPattern() async throws {
        // Given
        let rootDirectory = try temporaryPath()
        let sourcePath = rootDirectory.appending(component: "Scripts").appending(component: "**")

        // When
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
                type: .local
            ),
            TargetManifestMapperError.nonSpecificGeneratedResource(targetName: "Target", generatedSource: sourcePath)
        )
    }
}
