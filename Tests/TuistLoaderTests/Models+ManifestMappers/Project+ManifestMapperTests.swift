import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistGraph
@testable import TuistLoader
@testable import TuistSupportTesting

final class ProjectManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let project = ProjectDescription.Project(
            name: "Name",
            organizationName: "Organization",
            options: .options(
                automaticSchemesOptions: .enabled(
                    targetSchemesGrouping: .byNameSuffix(build: ["build"], test: ["test"], run: ["run"]),
                    codeCoverageEnabled: true,
                    testingOptions: [.parallelizable]
                ),
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
            additionalFiles: [.glob(pattern: "/file.swift")],
            resourceSynthesizers: []
        )
        fileHandler.stubExists = { _ in true }

        // When
        let got = try TuistGraph.Project.from(
            manifest: project,
            generatorPaths: .init(manifestDirectory: "/"),
            plugins: .none,
            externalDependencies: [:],
            resourceSynthesizerPathLocator: MockResourceSynthesizerPathLocator(),
            isExternal: false
        )

        // Then
        XCTAssertEqual(
            got,
            TuistGraph.Project(
                path: "/",
                sourceRootPath: "/",
                xcodeProjPath: "/XcodeName.xcodeproj",
                name: "Name",
                organizationName: "Organization",
                developmentRegion: "us",
                options: .init(
                    automaticSchemesOptions: .enabled(
                        targetSchemesGrouping: .byNameSuffix(build: ["build"], test: ["test"], run: ["run"]),
                        codeCoverageEnabled: true,
                        testingOptions: [.parallelizable]
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
                additionalFiles: [.file(path: "/file.swift")],
                resourceSynthesizers: [],
                lastUpgradeCheck: nil,
                isExternal: false
            )
        )
    }
}
