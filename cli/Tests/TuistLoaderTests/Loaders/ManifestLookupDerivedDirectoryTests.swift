import FileSystem
import FileSystemTesting
import Mockable
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistRootDirectoryLocator
import XcodeGraph

@testable import TuistLoader
@testable import TuistTesting

/// `Derived/FrameworkSearchPaths` is preserved across generations and holds one symbolic link per precompiled
/// framework into the binary cache. Recursive manifest lookups must not follow those links: on large graphs there
/// are thousands of them, and walking each destination tree dominated the time spent loading the workspace.
struct ManifestLookupDerivedDirectoryTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory)
    func recursiveManifestLoader_doesNotDescendIntoFrameworkSearchPathLinks() async throws {
        // Given
        let workspacePath = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = workspacePath.appending(components: "Projects", "App")
        try await createProjectWithFrameworkSearchPathLinks(at: projectPath, cacheDirectory: workspacePath)

        let manifestLoader = MockManifestLoading()
        given(manifestLoader)
            .loadWorkspace(at: .any, disableSandbox: .any)
            .willReturn(.test(projects: ["Projects/**"]))
        given(manifestLoader)
            .loadProject(at: .any, disableSandbox: .any)
            .willProduce { path, _ in .test(name: path.basename) }
        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(workspacePath)
        let subject = RecursiveManifestLoader(
            manifestLoader: manifestLoader,
            fileSystem: fileSystem,
            packageInfoMapper: MockPackageInfoMapping(),
            rootDirectoryLocator: rootDirectoryLocator
        )

        // When
        let got = try await subject.loadWorkspace(at: workspacePath, disableSandbox: false)

        // Then
        #expect(Set(got.projects.keys) == [projectPath])
    }

    @Test(.inTemporaryDirectory)
    func workspaceManifestMapper_doesNotDescendIntoFrameworkSearchPathLinks() async throws {
        // Given
        let workspacePath = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = workspacePath.appending(components: "Projects", "App")
        try await createProjectWithFrameworkSearchPathLinks(at: projectPath, cacheDirectory: workspacePath)

        // When
        let got = try await XcodeGraph.Workspace.from(
            manifest: .test(projects: ["Projects/**"]),
            path: workspacePath,
            generatorPaths: GeneratorPaths(manifestDirectory: workspacePath, rootDirectory: workspacePath),
            manifestLoader: MockManifestLoading(),
            fileSystem: fileSystem
        )

        // Then
        #expect(got.projects == [projectPath])
    }

    /// Lays out a project whose `Derived/FrameworkSearchPaths/Swift/App` directory links many times into a sizeable
    /// cached framework tree. The tree contains manifests so the tests can tell whether the links were followed.
    private func createProjectWithFrameworkSearchPathLinks(
        at projectPath: AbsolutePath,
        cacheDirectory: AbsolutePath
    ) async throws {
        try await fileSystem.makeDirectory(at: projectPath)
        try await fileSystem.touch(projectPath.appending(component: "Project.swift"))

        let cachedFramework = cacheDirectory.appending(components: "Binaries", "hash", "Module.framework")
        for directory in 0 ..< 20 {
            let headers = cachedFramework.appending(components: "Headers", "group\(directory)")
            try await fileSystem.makeDirectory(at: headers)
            for file in 0 ..< 10 {
                try await fileSystem.touch(headers.appending(component: "header\(file).h"))
            }
        }
        try await fileSystem.touch(cachedFramework.appending(component: "Project.swift"))
        try await fileSystem.touch(cachedFramework.appending(component: "Package.swift"))

        let linksDirectory = projectPath.appending(components: "Derived", "FrameworkSearchPaths", "Swift", "App")
        try await fileSystem.makeDirectory(at: linksDirectory)
        for index in 0 ..< 50 {
            try await fileSystem.createSymbolicLink(
                from: linksDirectory.appending(component: "Module\(index).framework"),
                to: cachedFramework
            )
            try await fileSystem.createSymbolicLink(
                from: linksDirectory.appending(component: "Module\(index).xcframework"),
                to: cachedFramework
            )
        }
    }
}
