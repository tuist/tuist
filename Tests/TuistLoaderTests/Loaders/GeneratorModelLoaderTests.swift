import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

class GeneratorModelLoaderTests: TuistUnitTestCase {
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

    override func setUp() {
        super.setUp()
        manifestLinter = MockManifestLinter()
    }

    override func tearDown() {
        manifestLinter = nil
        super.tearDown()
    }

    func test_loadProject() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let manifests = [
            temporaryPath: ProjectManifest.test(name: "SomeProject"),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = createGeneratorModelLoader(with: manifestLoader)

        // When
        let model = try subject.loadProject(at: temporaryPath)

        // Then
        XCTAssertEqual(model.name, "SomeProject")
    }

    func test_loadProject_withTargets() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let targetA = TargetManifest.test(name: "A", sources: [], resources: [])
        let targetB = TargetManifest.test(name: "B", sources: [], resources: [])
        let manifests = [
            temporaryPath: ProjectManifest.test(name: "Project",
                                                targets: [
                                                    targetA,
                                                    targetB,
                                                ]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = createGeneratorModelLoader(with: manifestLoader)

        // When
        let model = try subject.loadProject(at: temporaryPath)

        // Then
        XCTAssertEqual(model.targets.count, 2)
        try XCTAssertTargetMatchesManifest(target: model.targets[0], matches: targetA, at: temporaryPath, generatorPaths: generatorPaths)
        try XCTAssertTargetMatchesManifest(target: model.targets[1], matches: targetB, at: temporaryPath, generatorPaths: generatorPaths)
    }

    func test_loadProject_withManifestTargetOptionDisabled() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        try createFiles([
            "TuistConfig.swift",
        ])
        let projects = [
            temporaryPath: ProjectManifest.test(name: "Project",
                                                targets: [
                                                    .test(name: "A", sources: [], resources: []),
                                                    .test(name: "B", sources: [], resources: []),
                                                ]),
        ]

        let configs = [
            temporaryPath: TuistConfig.test(generationOptions: []),
        ]

        let manifestLoader = createManifestLoader(with: projects, configs: configs)
        let subject = createGeneratorModelLoader(with: manifestLoader)

        // When
        let model = try subject.loadProject(at: temporaryPath)

        // Then
        XCTAssertEqual(model.targets.map(\.name), [
            "A",
            "B",
        ])
    }

    func test_loadProject_withAdditionalFiles() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let files = try createFiles([
            "Documentation/README.md",
            "Documentation/guide.md",
        ])

        let manifests = [
            temporaryPath: ProjectManifest.test(name: "SomeProject",
                                                additionalFiles: [
                                                    "Documentation/**/*.md",
                                                ]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = createGeneratorModelLoader(with: manifestLoader)

        // When
        let model = try subject.loadProject(at: temporaryPath)

        // Then
        XCTAssertEqual(model.additionalFiles, files.map { .file(path: $0) })
    }

    func test_loadProject_withFolderReferences() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let files = try createFolders([
            "Stubs",
        ])

        let manifests = [
            temporaryPath: ProjectManifest.test(name: "SomeProject",
                                                additionalFiles: [
                                                    .folderReference(path: "Stubs"),
                                                ]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = createGeneratorModelLoader(with: manifestLoader)

        // When
        let model = try subject.loadProject(at: temporaryPath)

        // Then
        XCTAssertEqual(model.additionalFiles, files.map { .folderReference(path: $0) })
    }

    func test_loadProject_withCustomOrganizationName() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        try createFiles([
            "TuistConfig.swift",
        ])

        let manifests = [
            temporaryPath: ProjectManifest.test(name: "SomeProject",
                                                organizationName: "SomeOrganization",
                                                additionalFiles: [
                                                    .folderReference(path: "Stubs"),
                                                ]),
        ]
        let configs = [
            temporaryPath: ProjectDescription.TuistConfig.test(generationOptions: []),
        ]
        let manifestLoader = createManifestLoader(with: manifests, configs: configs)
        let subject = GeneratorModelLoader(manifestLoader: manifestLoader,
                                           manifestLinter: manifestLinter)

        // When
        let model = try subject.loadProject(at: temporaryPath)

        // Then
        XCTAssertEqual(model.organizationName, "SomeOrganization")
    }

    func test_loadWorkspace() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let manifests = [
            temporaryPath: WorkspaceManifest.test(name: "SomeWorkspace"),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = createGeneratorModelLoader(with: manifestLoader)

        // When
        let model = try subject.loadWorkspace(at: temporaryPath)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.projects, [])
    }

    func test_loadWorkspace_withProjects() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let projects = try createFolders([
            "A",
            "B",
        ])

        let manifests = [
            temporaryPath: WorkspaceManifest.test(name: "SomeWorkspace", projects: ["A", "B"]),
        ]

        let manifestLoader = createManifestLoader(with: manifests, projects: projects)
        let subject = createGeneratorModelLoader(with: manifestLoader)

        // When
        let model = try subject.loadWorkspace(at: temporaryPath)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.projects, projects)
    }

    func test_loadWorkspace_withAdditionalFiles() throws {
        let temporaryPath = try self.temporaryPath()
        let files = try createFiles([
            "Documentation/README.md",
            "Documentation/setup/README.md",
            "Playground.playground",
        ])

        let manifests = [
            temporaryPath: WorkspaceManifest.test(name: "SomeWorkspace",
                                                  projects: [],
                                                  additionalFiles: [
                                                      "Documentation/**/*.md",
                                                      "*.playground",
                                                  ]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = createGeneratorModelLoader(with: manifestLoader)

        // When
        let model = try subject.loadWorkspace(at: temporaryPath)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.additionalFiles, files.map { .file(path: $0) })
    }

    func test_loadWorkspace_withFolderReferences() throws {
        let temporaryPath = try self.temporaryPath()
        try createFiles([
            "Documentation/README.md",
            "Documentation/setup/README.md",
        ])

        let manifests = [
            temporaryPath: WorkspaceManifest.test(name: "SomeWorkspace",
                                                  projects: [],
                                                  additionalFiles: [
                                                      .folderReference(path: "Documentation"),
                                                  ]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = createGeneratorModelLoader(with: manifestLoader)

        // When
        let model = try subject.loadWorkspace(at: temporaryPath)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.additionalFiles, [
            .folderReference(path: temporaryPath.appending(RelativePath("Documentation"))),
        ])
    }

    func test_loadWorkspace_withInvalidProjectsPaths() throws {
        // Given
        let temporaryPath = try self.temporaryPath()

        let manifests = [
            temporaryPath: WorkspaceManifest.test(name: "SomeWorkspace", projects: ["A", "B"]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = createGeneratorModelLoader(with: manifestLoader)

        // When
        let model = try subject.loadWorkspace(at: temporaryPath)

        // Then
        XCTAssertPrinterOutputContains("""
        No projects found at: A
        No projects found at: B
        """)
        XCTAssertEqual(model.projects, [])
    }

    // MARK: - Helpers

    func createGeneratorModelLoader(with manifestLoader: ManifestLoading) -> GeneratorModelLoader {
        GeneratorModelLoader(manifestLoader: manifestLoader,
                             manifestLinter: manifestLinter)
    }

    func createManifestLoader(with projects: [AbsolutePath: ProjectDescription.Project],
                              configs: [AbsolutePath: ProjectDescription.Config] = [:]) -> ManifestLoading
    {
        let manifestLoader = MockManifestLoader()
        manifestLoader.loadProjectStub = { path in
            guard let manifest = projects[path] else {
                throw ManifestLoaderError.manifestNotFound(path)
            }
            return manifest
        }
        manifestLoader.loadConfigStub = { path in
            guard let manifest = configs[path] else {
                throw ManifestLoaderError.manifestNotFound(path)
            }
            return manifest
        }
        manifestLoader.manifestsAtStub = { path in
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

    func createManifestLoader(with workspaces: [AbsolutePath: ProjectDescription.Workspace],
                              projects: [AbsolutePath] = []) -> ManifestLoading
    {
        let manifestLoader = MockManifestLoader()
        manifestLoader.loadWorkspaceStub = { path in
            guard let manifest = workspaces[path] else {
                throw ManifestLoaderError.manifestNotFound(path)
            }
            return manifest
        }
        manifestLoader.manifestsAtStub = { path in
            projects.contains(path) ? Set([.project]) : Set([])
        }
        return manifestLoader
    }

    private func resolveProjectPath(projectPath: Path?, defaultPath: AbsolutePath, generatorPaths: GeneratorPaths) throws -> AbsolutePath {
        if let projectPath = projectPath { return try generatorPaths.resolve(path: projectPath) }
        return defaultPath
    }
}
