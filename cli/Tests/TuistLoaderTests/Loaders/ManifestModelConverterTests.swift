import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport
import XcodeGraph

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistTesting

struct ManifestModelConverterTests {
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

    private let manifestLinter: MockManifestLinter
    private let rootDirectoryLocator: MockRootDirectoryLocating
    private let contentHasher: MockContentHashing
    private let fileSystem = FileSystem()

    init() throws {
        manifestLinter = MockManifestLinter()
        rootDirectoryLocator = MockRootDirectoryLocating()
        contentHasher = MockContentHashing()

        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(temporaryPath)
    }

    @Test(.inTemporaryDirectory) func loadProject() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let manifest = ProjectManifest.test(name: "SomeProject")
        let manifestLoader = makeManifestLoader(with: [temporaryPath: manifest])
        let subject = makeSubject(with: manifestLoader)

        let model = try await subject.convert(
            manifest: manifest, path: temporaryPath, plugins: .none, externalDependencies: [:], type: .local
        )

        #expect(model.name == "SomeProject")
    }

    @Test(.inTemporaryDirectory) func loadProject_withTargets() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let targetA = TargetManifest.test(name: "A", sources: [], resources: [])
        let targetB = TargetManifest.test(name: "B", sources: [], resources: [])
        let manifest = ProjectManifest.test(name: "Project", targets: [targetA, targetB])
        let manifestLoader = makeManifestLoader(with: [temporaryPath: manifest])
        let subject = makeSubject(with: manifestLoader)

        let model = try await subject.convert(
            manifest: manifest, path: temporaryPath, plugins: .none, externalDependencies: [:], type: .local
        )

        #expect(model.targets.count == 2)
    }

    @Test(.inTemporaryDirectory) func loadProject_withAdditionalFiles() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let files = try await TuistTest.createFiles(["Documentation/README.md", "Documentation/guide.md"])
        let manifest = ProjectManifest.test(name: "SomeProject", additionalFiles: ["Documentation/**/*.md"])
        let manifestLoader = makeManifestLoader(with: [temporaryPath: manifest])
        let subject = makeSubject(with: manifestLoader)

        let model = try await subject.convert(
            manifest: manifest, path: temporaryPath, plugins: .none, externalDependencies: [:], type: .local
        )

        #expect(model.additionalFiles == files.map { .file(path: $0) })
    }

    @Test(.inTemporaryDirectory) func loadProject_withFolderReferences() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let files = try await TuistTest.makeDirectories(["Stubs"])
        let manifest = ProjectManifest.test(name: "SomeProject", additionalFiles: [.folderReference(path: "Stubs")])
        let manifestLoader = makeManifestLoader(with: [temporaryPath: manifest])
        let subject = makeSubject(with: manifestLoader)

        let model = try await subject.convert(
            manifest: manifest, path: temporaryPath, plugins: .none, externalDependencies: [:], type: .local
        )

        #expect(model.additionalFiles == files.map { .folderReference(path: $0) })
    }

    @Test(.inTemporaryDirectory) func loadProject_withCustomOrganizationName() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let manifest = ProjectManifest.test(
            name: "SomeProject", organizationName: "SomeOrganization",
            additionalFiles: [.folderReference(path: "Stubs")]
        )
        let manifestLoader = makeManifestLoader(with: [temporaryPath: manifest])
        let subject = makeSubject(with: manifestLoader)

        let model = try await subject.convert(
            manifest: manifest, path: temporaryPath, plugins: .none, externalDependencies: [:], type: .local
        )

        #expect(model.organizationName == "SomeOrganization")
    }

    @Test(.inTemporaryDirectory) func loadWorkspace() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let manifest = WorkspaceManifest.test(name: "SomeWorkspace")
        let manifestLoader = makeManifestLoader(with: [temporaryPath: manifest])
        let subject = makeSubject(with: manifestLoader)

        let model = try await subject.convert(manifest: manifest, path: temporaryPath)

        #expect(model.name == "SomeWorkspace")
        #expect(model.projects == [])
    }

    @Test(.inTemporaryDirectory) func loadWorkspace_withProjects() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let projects = try await TuistTest.makeDirectories(["A", "B"])
        try await TuistTest.createFiles(["A/Project.swift", "B/Project.swift"])
        let manifest = WorkspaceManifest.test(name: "SomeWorkspace", projects: ["A", "B"])
        let manifestLoader = makeManifestLoader(with: [temporaryPath: manifest], projects: projects)
        let subject = makeSubject(with: manifestLoader)

        let model = try await subject.convert(manifest: manifest, path: temporaryPath)

        #expect(model.name == "SomeWorkspace")
        #expect(model.projects == projects)
    }

    @Test(.inTemporaryDirectory) func loadWorkspace_withAdditionalFiles() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let files = try await TuistTest.createFiles([
            "Documentation/README.md", "Documentation/setup/README.md", "Playground.playground",
        ])
        let manifest = WorkspaceManifest.test(
            name: "SomeWorkspace", projects: [],
            additionalFiles: ["Documentation/**/*.md", "*.playground"]
        )
        let manifestLoader = makeManifestLoader(with: [temporaryPath: manifest])
        let subject = makeSubject(with: manifestLoader)

        let model = try await subject.convert(manifest: manifest, path: temporaryPath)

        #expect(model.name == "SomeWorkspace")
        #expect(model.additionalFiles == files.map { .file(path: $0) })
    }

    @Test(.inTemporaryDirectory) func loadWorkspace_withFolderReferences() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFiles(["Documentation/README.md", "Documentation/setup/README.md"])
        let manifest = WorkspaceManifest.test(
            name: "SomeWorkspace", projects: [],
            additionalFiles: [.folderReference(path: "Documentation")]
        )
        let manifestLoader = makeManifestLoader(with: [temporaryPath: manifest])
        let subject = makeSubject(with: manifestLoader)

        let model = try await subject.convert(manifest: manifest, path: temporaryPath)

        #expect(model.name == "SomeWorkspace")
        #expect(model.additionalFiles == [
            .folderReference(path: temporaryPath.appending(try RelativePath(validating: "Documentation"))),
        ])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func loadWorkspace_withInvalidProjectPath() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        try await fileSystem.makeDirectory(at: temporaryPath.appending(component: "Resources"))

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/Image.png")
        let model = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        TuistTest.expectLogs("No files found at: \(temporaryPath.appending(components: "Resources", "Image.png"))")
        #expect(model == [])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func loadWorkspace_withUnmatchedProjectGlob() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        try await fileSystem.makeDirectory(at: temporaryPath.appending(component: "Resources"))

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/**")
        let model = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        TuistTest.doesntExpectLogs("No files found at: \(temporaryPath.appending(components: "Resources", "**"))")
        #expect(model == [])
    }

    func makeSubject(with manifestLoader: ManifestLoading) -> ManifestModelConverter {
        ManifestModelConverter(
            manifestLoader: manifestLoader,
            rootDirectoryLocator: rootDirectoryLocator,
            contentHasher: contentHasher
        )
    }

    func makeManifestLoader(
        with projects: [AbsolutePath: ProjectDescription.Project],
        configs: [AbsolutePath: ProjectDescription.Config] = [:]
    ) -> ManifestLoading {
        let manifestLoader = MockManifestLoading()
        given(manifestLoader).loadProject(at: .any, disableSandbox: .any).willProduce { path, _ in
            guard let manifest = projects[path] else { throw ManifestLoaderError.manifestNotFound(path) }
            return manifest
        }
        given(manifestLoader).loadConfig(at: .any).willProduce { path in
            guard let manifest = configs[path] else { throw ManifestLoaderError.manifestNotFound(path) }
            return manifest
        }
        given(manifestLoader).manifests(at: .any).willProduce { path in
            var manifests = Set<Manifest>()
            if projects[path] != nil { manifests.insert(.project) }
            if configs[path] != nil { manifests.insert(.config) }
            return manifests
        }
        return manifestLoader
    }

    func makeManifestLoader(
        with workspaces: [AbsolutePath: ProjectDescription.Workspace],
        projects: [AbsolutePath] = []
    ) -> ManifestLoading {
        let manifestLoader = MockManifestLoading()
        given(manifestLoader).loadWorkspace(at: .any, disableSandbox: .any).willProduce { path, _ in
            guard let manifest = workspaces[path] else { throw ManifestLoaderError.manifestNotFound(path) }
            return manifest
        }
        given(manifestLoader).manifests(at: .any).willProduce { path in
            projects.contains(path) ? Set([.project]) : Set([])
        }
        return manifestLoader
    }

    private func resolveProjectPath(
        projectPath: Path?, defaultPath: AbsolutePath, generatorPaths: GeneratorPaths
    ) throws -> AbsolutePath {
        if let projectPath { return try generatorPaths.resolve(path: projectPath) }
        return defaultPath
    }
}
