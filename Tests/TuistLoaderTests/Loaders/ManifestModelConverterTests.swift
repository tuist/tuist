import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class ManifestModelConverterTests: TuistUnitTestCase {
    typealias WorkspaceManifest = ProjectDescription.Workspace
    typealias ProjectManifest = ProjectDescription.Project
    typealias TargetManifest = ProjectDescription.Target
    typealias SettingsManifest = ProjectDescription.Settings
    typealias ConfigurationManifest = ProjectDescription.Configuration
    typealias HeadersManifest = ProjectDescription.Headers
    typealias SchemeManifest = ProjectDescription.Scheme
    typealias BuildActionManifest = ProjectDescription.BuildAction
    typealias TestActionManifest = ProjectDescription.TestAction
    typealias RunActionManifest = ProjectDescription.RunAction
    typealias ArgumentsManifest = ProjectDescription.Arguments

    private var manifestLinter: MockManifestLinter!
    private var rootDirectoryLocator: MockRootDirectoryLocating!

    override func setUpWithError() throws {
        super.setUp()
        manifestLinter = MockManifestLinter()
        rootDirectoryLocator = MockRootDirectoryLocating()

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(try temporaryPath())
    }

    override func tearDown() {
        manifestLinter = nil
        rootDirectoryLocator = nil
        super.tearDown()
    }

    func test_loadProject() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let manifest = ProjectManifest.test(name: "SomeProject")
        let manifestLoader = makeManifestLoader(with: [
            temporaryPath: manifest,
        ])
        let subject = makeSubject(with: manifestLoader)

        // When
        let model = try await subject.convert(
            manifest: manifest,
            path: temporaryPath,
            plugins: .none,
            externalDependencies: [:],
            type: .local
        )

        // Then
        XCTAssertEqual(model.name, "SomeProject")
    }

    func test_loadProject_withTargets() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
        )
        let targetA = TargetManifest.test(name: "A", sources: [], resources: [])
        let targetB = TargetManifest.test(name: "B", sources: [], resources: [])
        let manifest = ProjectManifest.test(
            name: "Project",
            targets: [
                targetA,
                targetB,
            ]
        )
        let manifestLoader = makeManifestLoader(with: [
            temporaryPath: manifest,
        ])
        let subject = makeSubject(with: manifestLoader)

        // When
        let model = try await subject.convert(
            manifest: manifest,
            path: temporaryPath,
            plugins: .none,
            externalDependencies: [:],
            type: .local
        )

        // Then
        XCTAssertEqual(model.targets.count, 2)
        try XCTAssertTargetMatchesManifest(
            target: try XCTUnwrap(model.targets["A"]),
            matches: targetA,
            at: temporaryPath,
            generatorPaths: generatorPaths
        )
        try XCTAssertTargetMatchesManifest(
            target: try XCTUnwrap(model.targets["B"]),
            matches: targetB,
            at: temporaryPath,
            generatorPaths: generatorPaths
        )
    }

    func test_loadProject_withAdditionalFiles() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let files = try await createFiles([
            "Documentation/README.md",
            "Documentation/guide.md",
        ])
        let manifest = ProjectManifest.test(
            name: "SomeProject",
            additionalFiles: [
                "Documentation/**/*.md",
            ]
        )
        let manifestLoader = makeManifestLoader(with: [
            temporaryPath: manifest,
        ])
        let subject = makeSubject(with: manifestLoader)

        // When
        let model = try await subject.convert(
            manifest: manifest,
            path: temporaryPath,
            plugins: .none,
            externalDependencies: [:],
            type: .local
        )

        // Then
        XCTAssertEqual(model.additionalFiles, files.map { .file(path: $0) })
    }

    func test_loadProject_withFolderReferences() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let files = try createFolders([
            "Stubs",
        ])
        let manifest = ProjectManifest.test(
            name: "SomeProject",
            additionalFiles: [
                .folderReference(path: "Stubs"),
            ]
        )
        let manifestLoader = makeManifestLoader(with: [
            temporaryPath: manifest,
        ])
        let subject = makeSubject(with: manifestLoader)

        // When
        let model = try await subject.convert(
            manifest: manifest,
            path: temporaryPath,
            plugins: .none,
            externalDependencies: [:],
            type: .local
        )

        // Then
        XCTAssertEqual(model.additionalFiles, files.map { .folderReference(path: $0) })
    }

    func test_loadProject_withCustomOrganizationName() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let manifest = ProjectManifest.test(
            name: "SomeProject",
            organizationName: "SomeOrganization",
            additionalFiles: [
                .folderReference(path: "Stubs"),
            ]
        )
        let manifestLoader = makeManifestLoader(with: [
            temporaryPath: manifest,
        ])
        let subject = makeSubject(with: manifestLoader)

        // When
        let model = try await subject.convert(
            manifest: manifest,
            path: temporaryPath,
            plugins: .none,
            externalDependencies: [:],
            type: .local
        )

        // Then
        XCTAssertEqual(model.organizationName, "SomeOrganization")
    }

    func test_loadWorkspace() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let manifest = WorkspaceManifest.test(name: "SomeWorkspace")
        let manifestLoader = makeManifestLoader(with: [
            temporaryPath: manifest,
        ])
        let subject = makeSubject(with: manifestLoader)

        // When
        let model = try await subject.convert(manifest: manifest, path: temporaryPath)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.projects, [])
    }

    func test_loadWorkspace_withProjects() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let projects = try createFolders([
            "A",
            "B",
        ])
        try await createFiles(["A/Project.swift", "B/Project.swift"])

        let manifest = WorkspaceManifest.test(name: "SomeWorkspace", projects: ["A", "B"])
        let manifests = [
            temporaryPath: manifest,
        ]

        let manifestLoader = makeManifestLoader(with: manifests, projects: projects)
        let subject = makeSubject(with: manifestLoader)

        // When
        let model = try await subject.convert(manifest: manifest, path: temporaryPath)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.projects, projects)
    }

    func test_loadWorkspace_withAdditionalFiles() async throws {
        let temporaryPath = try temporaryPath()
        let files = try await createFiles([
            "Documentation/README.md",
            "Documentation/setup/README.md",
            "Playground.playground",
        ])

        let manifest = WorkspaceManifest.test(
            name: "SomeWorkspace",
            projects: [],
            additionalFiles: [
                "Documentation/**/*.md",
                "*.playground",
            ]
        )

        let manifestLoader = makeManifestLoader(with: [
            temporaryPath: manifest,
        ])

        let subject = makeSubject(with: manifestLoader)

        // When
        let model = try await subject.convert(manifest: manifest, path: temporaryPath)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.additionalFiles, files.map { .file(path: $0) })
    }

    func test_loadWorkspace_withFolderReferences() async throws {
        let temporaryPath = try temporaryPath()
        try await createFiles([
            "Documentation/README.md",
            "Documentation/setup/README.md",
        ])
        let manifest = WorkspaceManifest.test(
            name: "SomeWorkspace",
            projects: [],
            additionalFiles: [
                .folderReference(path: "Documentation"),
            ]
        )
        let manifestLoader = makeManifestLoader(with: [
            temporaryPath: manifest,
        ])
        let subject = makeSubject(with: manifestLoader)

        // When
        let model = try await subject.convert(manifest: manifest, path: temporaryPath)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(
            model.additionalFiles,
            [
                .folderReference(
                    path: temporaryPath.appending(try RelativePath(validating: "Documentation"))
                ),
            ]
        )
    }

    func test_loadWorkspace_withInvalidProjectPath() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try temporaryPath()
            let rootDirectory = temporaryPath
            let generatorPaths = GeneratorPaths(
                manifestDirectory: temporaryPath,
                rootDirectory: rootDirectory
            )

            try await fileSystem.makeDirectory(at: rootDirectory.appending(component: "Resources"))

            let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/Image.png")

            // When
            let model = try await XcodeGraph.ResourceFileElement.from(
                manifest: manifest,
                generatorPaths: generatorPaths,
                fileSystem: fileSystem
            )

            // Then
            XCTAssertPrinterOutputContains(
                "No files found at: \(rootDirectory.appending(components: "Resources", "Image.png"))"
            )
            XCTAssertEqual(model, [])
        }
    }

    func test_loadWorkspace_withUnmatchedProjectGlob() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try temporaryPath()
            let rootDirectory = temporaryPath
            let generatorPaths = GeneratorPaths(
                manifestDirectory: temporaryPath,
                rootDirectory: rootDirectory
            )

            try await fileSystem.makeDirectory(at: rootDirectory.appending(component: "Resources"))

            let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/**")

            // When
            let model = try await XcodeGraph.ResourceFileElement.from(
                manifest: manifest,
                generatorPaths: generatorPaths,
                fileSystem: fileSystem
            )

            // Then
            XCTAssertPrinterOutputNotContains(
                "No files found at: \(rootDirectory.appending(components: "Resources", "**"))"
            )
            XCTAssertEqual(model, [])
        }
    }

    // MARK: - Helpers

    func makeSubject(with manifestLoader: ManifestLoading) -> ManifestModelConverter {
        ManifestModelConverter(
            manifestLoader: manifestLoader,
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    func makeManifestLoader(
        with projects: [AbsolutePath: ProjectDescription.Project],
        configs: [AbsolutePath: ProjectDescription.Config] = [:]
    ) -> ManifestLoading {
        let manifestLoader = MockManifestLoading()
        given(manifestLoader)
            .loadProject(at: .any)
            .willProduce { path in
                guard let manifest = projects[path] else {
                    throw ManifestLoaderError.manifestNotFound(path)
                }
                return manifest
            }
        given(manifestLoader)
            .loadConfig(at: .any)
            .willProduce { path in
                guard let manifest = configs[path] else {
                    throw ManifestLoaderError.manifestNotFound(path)
                }
                return manifest
            }
        given(manifestLoader)
            .manifests(at: .any)
            .willProduce { path in
                var manifests = Set<Manifest>()
                if projects[path] != nil {
                    manifests.insert(.project)
                }

                if configs[path] != nil {
                    manifests.insert(.config)
                }
                return manifests
            }
        return manifestLoader
    }

    func makeManifestLoader(
        with workspaces: [AbsolutePath: ProjectDescription.Workspace],
        projects: [AbsolutePath] = []
    ) -> ManifestLoading {
        let manifestLoader = MockManifestLoading()
        given(manifestLoader)
            .loadWorkspace(at: .any)
            .willProduce { path in
                guard let manifest = workspaces[path] else {
                    throw ManifestLoaderError.manifestNotFound(path)
                }
                return manifest
            }
        given(manifestLoader)
            .manifests(at: .any)
            .willProduce { path in
                projects.contains(path) ? Set([.project]) : Set([])
            }
        return manifestLoader
    }

    private func resolveProjectPath(
        projectPath: Path?,
        defaultPath: AbsolutePath,
        generatorPaths: GeneratorPaths
    ) throws -> AbsolutePath {
        if let projectPath { return try generatorPaths.resolve(path: projectPath) }
        return defaultPath
    }
}
