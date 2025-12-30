import _NIOFileSystem
import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import ProjectDescription
import Testing
import TuistCore
import struct TuistCore.Plugins
import TuistSupport
import TuistTesting

@testable import TuistLoader
@testable import TuistTesting

class CachedManifestLoaderTests {
    private var cacheDirectory: AbsolutePath!
    private var manifestLoader = MockManifestLoading()
    private var projectDescriptionHelpersHasher = MockProjectDescriptionHelpersHasher()
    private var helpersDirectoryLocator = MockHelpersDirectoryLocator()
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var workspaceManifests: [AbsolutePath: Workspace] = [:]
    private var projectManifests: [AbsolutePath: Project] = [:]
    private var configManifests: [AbsolutePath: ProjectDescription.Config] = [:]
    private var pluginManifests: [AbsolutePath: ProjectDescription.Plugin] = [:]
    private var recordedLoadWorkspaceCalls: Int = 0
    private var recordedLoadProjectCalls: Int = 0
    private var recordedLoadConfigCalls: Int = 0
    private var recordedLoadPluginCalls: Int = 0
    private let fileSystem = FileSystem()
    private let fileHandler = FileHandler.shared
    private var subject: CachedManifestLoader!

    init() throws {
        cacheDirectoriesProvider = .init()
        cacheDirectory = try #require(FileSystem.temporaryTestDirectory).appending(components: "tuist", "Cache", "Manifests")
        cacheDirectoriesProvider = .init()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.manifests))
            .willReturn(cacheDirectory)

        subject = try createSubject()

        given(manifestLoader)
            .loadWorkspace(at: .any, disableSandbox: .any)
            .willProduce { [unowned self] path, _ in
                guard let manifest = workspaceManifests[path] else {
                    throw ManifestLoaderError.manifestNotFound(.workspace, path)
                }
                recordedLoadWorkspaceCalls += 1
                return manifest
            }

        given(manifestLoader)
            .loadProject(at: .any, disableSandbox: .any)
            .willProduce { [unowned self] path, _ in
                guard let manifest = projectManifests[path] else {
                    throw ManifestLoaderError.manifestNotFound(.project, path)
                }
                recordedLoadProjectCalls += 1
                return manifest
            }

        given(manifestLoader)
            .loadConfig(at: .any)
            .willProduce { [unowned self] path in
                guard let manifest = configManifests[path] else {
                    throw ManifestLoaderError.manifestNotFound(.config, path)
                }
                recordedLoadConfigCalls += 1
                return manifest
            }

        given(manifestLoader)
            .loadPlugin(at: .any)
            .willProduce { [unowned self] path in
                guard let manifest = pluginManifests[path] else {
                    throw ManifestLoaderError.manifestNotFound(.plugin, path)
                }
                recordedLoadPluginCalls += 1
                return manifest
            }
    }

    // MARK: - Tests

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_manifestNotCached() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)

        // When
        let result = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(result == project)
        #expect(result.name == "App")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_manifestCached() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)

        // When
        _ = try await subject.loadProject(at: path, disableSandbox: false)
        _ = try await subject.loadProject(at: path, disableSandbox: false)
        _ = try await subject.loadProject(at: path, disableSandbox: false)
        let result = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(result == project)
        #expect(recordedLoadProjectCalls == 1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_manifestHashChanged() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let originalProject = Project.test(name: "Original")
        try await stubProject(originalProject, at: path)
        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // When
        let modifiedProject = Project.test(name: "Modified")
        try await stubProject(modifiedProject, at: path)
        let result = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(result == modifiedProject)
        #expect(result.name == "Modified")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_helpersHashChanged() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)
        try stubHelpers(withHash: "hash")

        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // When
        try stubHelpers(withHash: "updatedHash")
        subject = try createSubject() // we need to re-create the subject as it internally caches hashes
        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(recordedLoadProjectCalls == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_pluginsHashChanged() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)
        given(manifestLoader)
            .register(plugins: .any)
            .willReturn()
        try stubPlugins(withHash: "hash")

        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // When
        try stubPlugins(withHash: "updatedHash")
        subject = try createSubject() // we need to re-create the subject as it internally caches hashes
        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(recordedLoadProjectCalls == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_environmentVariablesRemainTheSame() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)
        let mockEnvironment = try #require(TuistSupport.Environment.mocked)
        mockEnvironment.manifestLoadingVariables = ["NAME": "A"]

        // When
        _ = try await subject.loadProject(at: path, disableSandbox: false)
        _ = try await subject.loadProject(at: path, disableSandbox: false)
        _ = try await subject.loadProject(at: path, disableSandbox: false)
        let result = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(result == project)
        #expect(recordedLoadProjectCalls == 1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_environmentVariablesChange() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)
        let mockEnvironment = try #require(TuistSupport.Environment.mocked)
        mockEnvironment.manifestLoadingVariables = ["NAME": "A"]
        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // When
        mockEnvironment.manifestLoadingVariables = ["NAME": "B"]
        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(recordedLoadProjectCalls == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_tuistVersionRemainsTheSame() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)
        subject = try createSubject(tuistVersion: "1.0")
        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // When
        subject = try createSubject(tuistVersion: "1.0")
        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(recordedLoadProjectCalls == 1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_tuistVersionChanged() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)
        subject = try createSubject(tuistVersion: "1.0")
        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // When
        subject = try createSubject(tuistVersion: "2.0")
        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(recordedLoadProjectCalls == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_corruptedCache() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)
        _ = try await subject.loadProject(at: path, disableSandbox: false)

        // When
        try corruptFiles(at: cacheDirectory)
        let result = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(result == project)
        #expect(recordedLoadProjectCalls == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func load_missingManifest() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")

        // When / Then
        await #expect(throws: ManifestLoaderError.manifestNotFound(.project, path), performing: {
            try await self.subject.loadProject(at: path, disableSandbox: false)
        })
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func validate_projectExists() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        given(manifestLoader)
            .manifests(at: .any)
            .willReturn([.project])
        given(manifestLoader)
            .validateHasRootManifest(at: .value(path))
            .willReturn()

        // When / Then
        try await subject.validateHasRootManifest(at: path)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func validate_workspaceExists() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        given(manifestLoader)
            .validateHasRootManifest(at: .value(path))
            .willReturn()
        given(manifestLoader)
            .manifests(at: .any)
            .willReturn([.workspace])

        // When / Then
        try await subject.validateHasRootManifest(at: path)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func validate_manifestDoesNotExist() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        given(manifestLoader)
            .validateHasRootManifest(at: .value(path))
            .willThrow(ManifestLoaderError.manifestNotFound(path))

        // When / Then
        await #expect(throws: ManifestLoaderError.manifestNotFound(path), performing: {
            try await self.subject.validateHasRootManifest(at: path)
        })
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func notThrowing_fileAlreadyExistsNIOError() async throws {
        // Given
        let fileSystem = MockFileSystem()
        fileSystem.writeTextOverride = { _, _, _ in
            throw _NIOFileSystem.FileSystemError(
                code: .fileAlreadyExists,
                message: "",
                cause: nil,
                location: .init(function: "", file: "", line: 0)
            )
        }

        subject = try createSubject(fileSystem: fileSystem)

        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)

        // When
        let result = try await subject.loadProject(at: path, disableSandbox: false)

        // Then
        #expect(result == project)
        #expect(result.name == "App")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func throwing_otherNIOErrors() async throws {
        // Given
        let expectedError = _NIOFileSystem.FileSystemError(
            code: .invalidArgument,
            message: "",
            cause: nil,
            location: .init(function: "", file: "", line: 0)
        )
        let fileSystem = MockFileSystem()
        fileSystem.writeTextOverride = { _, _, _ in
            throw expectedError
        }

        subject = try createSubject(fileSystem: fileSystem)

        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let project = Project.test(name: "App")
        try await stubProject(project, at: path)

        // When/Then
        await #expect(throws: expectedError, performing: {
            try await self.subject.loadProject(at: path, disableSandbox: false)
        })
    }

    // MARK: - Helpers

    private func createSubject(tuistVersion: String = "1.0", fileSystem: FileSysteming? = nil) throws -> CachedManifestLoader {
        CachedManifestLoader(
            manifestLoader: manifestLoader,
            projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
            helpersDirectoryLocator: helpersDirectoryLocator,
            fileSystem: fileSystem ?? self.fileSystem,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            tuistVersion: tuistVersion
        )
    }

    private func stubWorkspace(
        _ workspace: Workspace,
        at path: AbsolutePath
    ) throws {
        let manifestPath = path.appending(component: Manifest.workspace.fileName(path))
        try fileHandler.touch(manifestPath)
        let manifestData = try JSONEncoder().encode(workspace)
        try fileHandler.write(String(data: manifestData, encoding: .utf8)!, path: manifestPath, atomically: true)
        workspaceManifests[path] = workspace
    }

    private func stubProject(
        _ project: Project,
        at path: AbsolutePath
    ) async throws {
        let manifestPath = path.appending(component: Manifest.project.fileName(path))
        if try await !fileSystem.exists(manifestPath.parentDirectory) {
            try await fileSystem.makeDirectory(at: manifestPath.parentDirectory)
        }
        let manifestData = try JSONEncoder().encode(project)
        if try await fileSystem.exists(manifestPath) {
            try await fileSystem.remove(manifestPath)
        }
        try await fileSystem.writeText(String(data: manifestData, encoding: .utf8)!, at: manifestPath)
        projectManifests[path] = project
    }

    private func stub(
        deprecatedManifest manifest: ProjectDescription.Config,
        at path: AbsolutePath
    ) throws {
        let manifestPath = path.appending(component: Manifest.config.fileName(path))
        try fileHandler.touch(manifestPath)
        let manifestData = try JSONEncoder().encode(manifest)
        try fileHandler.write(String(data: manifestData, encoding: .utf8)!, path: manifestPath, atomically: true)
        configManifests[path] = manifest
    }

    private func stubHelpers(withHash hash: String) throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(components: "Tuist", "ProjectDescriptionHelpers")
        helpersDirectoryLocator.locateStub = path
        projectDescriptionHelpersHasher.stubHash = { _ in
            hash
        }
    }

    private func stubPlugins(withHash hash: String) throws {
        let plugin = ProjectDescription.Plugin(name: "TestPlugin")
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "TestPlugin")
        let manifestPath = path.appending(component: Manifest.plugin.fileName(path))
        try fileHandler.touch(manifestPath)
        let manifestData = try JSONEncoder().encode(plugin)
        try fileHandler.write(String(data: manifestData, encoding: .utf8)!, path: manifestPath, atomically: true)
        pluginManifests[path] = plugin

        let plugins = Plugins.test(projectDescriptionHelpers: [
            .init(name: "TestPlugin", path: path, location: .local),
        ])

        projectDescriptionHelpersHasher.stubHash = { _ in hash }
        try subject.register(plugins: plugins)
    }

    private func corruptFiles(at path: AbsolutePath) throws {
        for filePath in try fileHandler.contentsOfDirectory(path) {
            try fileHandler.write("corruptedData", path: filePath, atomically: true)
        }
    }
}

extension _NIOFileSystem.FileSystemError: Equatable {
    public static func == (lhs: _NIOFileSystem.FileSystemError, rhs: _NIOFileSystem.FileSystemError) -> Bool {
        return lhs.code == rhs.code && lhs.message == rhs.message && lhs.location == rhs.location
    }
}
