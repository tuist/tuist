import Foundation
import MockableTest
import Path
import ProjectDescription
import TuistCore
import struct TuistCore.Plugins
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class CachedManifestLoaderTests: TuistUnitTestCase {
    private var cacheDirectory: AbsolutePath!
    private var manifestLoader = MockManifestLoading()
    private var projectDescriptionHelpersHasher = MockProjectDescriptionHelpersHasher()
    private var helpersDirectoryLocator = MockHelpersDirectoryLocator()
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var cacheDirectoriesProviderFactory: MockCacheDirectoriesProviderFactoring!
    private var workspaceManifests: [AbsolutePath: Workspace] = [:]
    private var projectManifests: [AbsolutePath: Project] = [:]
    private var configManifests: [AbsolutePath: ProjectDescription.Config] = [:]
    private var pluginManifests: [AbsolutePath: ProjectDescription.Plugin] = [:]
    private var recordedLoadWorkspaceCalls: Int = 0
    private var recordedLoadProjectCalls: Int = 0
    private var recordedLoadConfigCalls: Int = 0
    private var recordedLoadPluginCalls: Int = 0

    private var subject: CachedManifestLoader!

    override func setUp() {
        super.setUp()

        do {
            cacheDirectoriesProvider = .init()
            cacheDirectory = try temporaryPath().appending(components: "tuist", "Cache", "Manifests")
            cacheDirectoriesProviderFactory = .init()
            given(cacheDirectoriesProviderFactory)
                .cacheDirectories()
                .willReturn(cacheDirectoriesProvider)
            given(cacheDirectoriesProvider)
                .cacheDirectory(for: .value(.manifests))
                .willReturn(cacheDirectory)
        } catch {
            XCTFail("Failed to create temporary directory")
        }

        subject = createSubject()

        given(manifestLoader)
            .loadWorkspace(at: .any)
            .willProduce { [unowned self] path in
                guard let manifest = workspaceManifests[path] else {
                    throw ManifestLoaderError.manifestNotFound(.workspace, path)
                }
                recordedLoadWorkspaceCalls += 1
                return manifest
            }

        given(manifestLoader)
            .loadProject(at: .any)
            .willProduce { [unowned self] path in
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

    override func tearDown() {
        subject = nil
        cacheDirectory = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_load_manifestNotCached() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)

        // When
        let result = try await subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, project)
        XCTAssertEqual(result.name, "App")
    }

    func test_load_manifestCached() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)

        // When
        _ = try await subject.loadProject(at: path)
        _ = try await subject.loadProject(at: path)
        _ = try await subject.loadProject(at: path)
        let result = try await subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, project)
        XCTAssertEqual(recordedLoadProjectCalls, 1)
    }

    func test_load_manifestHashChanged() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let originalProject = Project.test(name: "Original")
        try stubProject(originalProject, at: path)
        _ = try await subject.loadProject(at: path)

        // When
        let modifiedProject = Project.test(name: "Modified")
        try stubProject(modifiedProject, at: path)
        let result = try await subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, modifiedProject)
        XCTAssertEqual(result.name, "Modified")
    }

    func test_load_helpersHashChanged() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        try stubHelpers(withHash: "hash")

        _ = try await subject.loadProject(at: path)

        // When
        try stubHelpers(withHash: "updatedHash")
        subject = createSubject() // we need to re-create the subject as it internally caches hashes
        _ = try await subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_pluginsHashChanged() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        given(manifestLoader)
            .register(plugins: .any)
            .willReturn()
        try stubPlugins(withHash: "hash")

        _ = try await subject.loadProject(at: path)

        // When
        try stubPlugins(withHash: "updatedHash")
        subject = createSubject() // we need to re-create the subject as it internally caches hashes
        _ = try await subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_environmentVariablesRemainTheSame() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        environment.manifestLoadingVariables = ["NAME": "A"]

        // When
        _ = try await subject.loadProject(at: path)
        _ = try await subject.loadProject(at: path)
        _ = try await subject.loadProject(at: path)
        let result = try await subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, project)
        XCTAssertEqual(recordedLoadProjectCalls, 1)
    }

    func test_load_environmentVariablesChange() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        environment.manifestLoadingVariables = ["NAME": "A"]
        _ = try await subject.loadProject(at: path)

        // When
        environment.manifestLoadingVariables = ["NAME": "B"]
        _ = try await subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_tuistVersionRemainsTheSame() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        subject = createSubject(tuistVersion: "1.0")
        _ = try await subject.loadProject(at: path)

        // When
        subject = createSubject(tuistVersion: "1.0")
        _ = try await subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 1)
    }

    func test_load_tuistVersionChanged() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        subject = createSubject(tuistVersion: "1.0")
        _ = try await subject.loadProject(at: path)

        // When
        subject = createSubject(tuistVersion: "2.0")
        _ = try await subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_corruptedCache() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        _ = try await subject.loadProject(at: path)

        // When
        try corruptFiles(at: cacheDirectory)
        let result = try await subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, project)
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_missingManifest() async throws {
        // Given
        let path = try temporaryPath().appending(component: "App")

        // When / Then
        await XCTAssertThrowsSpecific(
            { try await self.subject.loadProject(at: path) },
            ManifestLoaderError.manifestNotFound(.project, path)
        )
    }

    func test_validate_projectExists() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        given(manifestLoader)
            .manifests(at: .any)
            .willReturn([.project])
        given(manifestLoader)
            .validateHasRootManifest(at: .value(path))
            .willReturn()

        // When / Then
        try subject.validateHasRootManifest(at: path)
    }

    func test_validate_workspaceExists() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        given(manifestLoader)
            .validateHasRootManifest(at: .value(path))
            .willReturn()
        given(manifestLoader)
            .manifests(at: .any)
            .willReturn([.workspace])

        // When / Then
        try subject.validateHasRootManifest(at: path)
    }

    func test_validate_manifestDoesNotExist() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        given(manifestLoader)
            .validateHasRootManifest(at: .value(path))
            .willThrow(ManifestLoaderError.manifestNotFound(path))

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.validateHasRootManifest(at: path),
            ManifestLoaderError.manifestNotFound(path)
        )
    }

    // MARK: - Helpers

    private func createSubject(tuistVersion: String = "1.0") -> CachedManifestLoader {
        CachedManifestLoader(
            manifestLoader: manifestLoader,
            projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
            helpersDirectoryLocator: helpersDirectoryLocator,
            fileHandler: fileHandler,
            environment: environment,
            cacheDirectoryProviderFactory: cacheDirectoriesProviderFactory,
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
    ) throws {
        let manifestPath = path.appending(component: Manifest.project.fileName(path))
        try fileHandler.touch(manifestPath)
        let manifestData = try JSONEncoder().encode(project)
        try fileHandler.write(String(data: manifestData, encoding: .utf8)!, path: manifestPath, atomically: true)
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
        let path = try temporaryPath().appending(components: "Tuist", "ProjectDescriptionHelpers")
        helpersDirectoryLocator.locateStub = path
        projectDescriptionHelpersHasher.stubHash = { _ in
            hash
        }
    }

    private func stubPlugins(withHash hash: String) throws {
        let plugin = ProjectDescription.Plugin(name: "TestPlugin")
        let path = try temporaryPath().appending(component: "TestPlugin")
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
