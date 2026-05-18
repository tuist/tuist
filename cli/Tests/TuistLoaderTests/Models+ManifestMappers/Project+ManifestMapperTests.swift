import Foundation
import ProjectDescription
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistTesting
@testable import XcodeGraph

final class ProjectManifestMapperTests: TuistUnitTestCase {
    func test_from() async throws {
        // Given
        let swiftFilePath = try temporaryPath()
            .appending(component: "file.swift")
        try await fileSystem.touch(swiftFilePath)
        let project = ProjectDescription.Project(
            name: "Name",
            organizationName: "Organization",
            classPrefix: "ClassPrefix",
            options: .options(
                automaticSchemesOptions: .enabled(
                    targetSchemesGrouping: .byNameSuffix(build: ["build"], test: ["test"], run: ["run"]),
                    codeCoverageEnabled: true,
                    parallelization: .enabled
                ),
                defaultKnownRegions: ["en-US", "Base"],
                developmentRegion: "us",
                disableBundleAccessors: true,
                disableShowEnvironmentVarsInScriptPhases: true,
                disableSynthesizedResourceAccessors: true,
                textSettings: .textSettings(usesTabs: true, indentWidth: 1, tabWidth: 2, wrapsLines: true),
                xcodeProjectName: "XcodeName"
            ),
            packages: [
                .remote(url: "url", requirement: .branch("b")),
                .local(path: "/path"),
            ],
            targets: [],
            schemes: [],
            fileHeaderTemplate: .string("123"),
            additionalFiles: [.glob(pattern: .path(swiftFilePath.pathString))],
            resourceSynthesizers: []
        )

        // When
        let got = try await XcodeGraph.Project.from(
            manifest: project,
            generatorPaths: .init(manifestDirectory: "/", rootDirectory: "/"),
            plugins: .none,
            externalDependencies: [:],
            resourceSynthesizerPathLocator: MockResourceSynthesizerPathLocator(),
            type: .local,
            fileSystem: fileSystem,
            contentHasher: MockContentHashing()
        )

        // Then
        XCTAssertBetterEqual(
            got,
            XcodeGraph.Project(
                path: "/",
                sourceRootPath: "/",
                xcodeProjPath: "/XcodeName.xcodeproj",
                name: "Name",
                organizationName: "Organization",
                classPrefix: "ClassPrefix",
                defaultKnownRegions: ["en-US", "Base"],
                developmentRegion: "us",
                options: .init(
                    automaticSchemesOptions: .enabled(
                        targetSchemesGrouping: .byNameSuffix(build: ["build"], test: ["test"], run: ["run"]),
                        codeCoverageEnabled: true,
                        parallelization: .all,
                        randomExecutionOrdering: false
                    ),
                    disableBundleAccessors: true,
                    disableShowEnvironmentVarsInScriptPhases: true,
                    disableSynthesizedResourceAccessors: true,
                    textSettings: .init(usesTabs: true, indentWidth: 1, tabWidth: 2, wrapsLines: true)
                ),
                settings: .default,
                filesGroup: .group(name: "Project"),
                targets: [],
                packages: [
                    .remote(url: "url", requirement: .branch("b")),
                    .local(path: "/path"),
                ],
                schemes: [],
                ideTemplateMacros: .init(fileHeader: "123"),
                additionalFiles: [.file(path: swiftFilePath)],
                resourceSynthesizers: [],
                lastUpgradeCheck: nil,
                type: .local
            )
        )
    }

    func test_from_mapsSwiftTestingOnlyParallelization() throws {
        let manifest = ProjectDescription.Project.Options.options(
            automaticSchemesOptions: .enabled(parallelization: .swiftTestingOnly)
        )

        let model = XcodeGraph.Project.Options.from(manifest: manifest)

        XCTAssertEqual(model.parallelization, .swiftTestingOnly)
        XCTAssertFalse(model.randomExecutionOrdering)
    }

    func test_from_mapsParallelizationEnabled() throws {
        let manifest = ProjectDescription.Project.Options.options(
            automaticSchemesOptions: .enabled(parallelization: .enabled, randomExecutionOrdering: true)
        )

        let model = XcodeGraph.Project.Options.from(manifest: manifest)

        XCTAssertEqual(model.parallelization, .all)
        XCTAssertTrue(model.randomExecutionOrdering)
    }

    func test_from_mapsDeprecatedTestingOptionsParallelizable() throws {
        let manifest = ProjectDescription.Project.Options.options(
            automaticSchemesOptions: .enabled(testingOptions: [.parallelizable, .randomExecutionOrdering])
        )

        let model = XcodeGraph.Project.Options.from(manifest: manifest)

        XCTAssertEqual(model.parallelization, .all)
        XCTAssertTrue(model.randomExecutionOrdering)
    }
}
