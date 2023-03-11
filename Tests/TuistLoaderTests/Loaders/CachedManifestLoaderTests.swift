import Foundation
import ProjectDescription
import TSCBasic
import struct TuistGraph.Plugins
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class CachedManifestLoaderTests: TuistUnitTestCase {
    private var cacheDirectory: AbsolutePath!
    private var manifestLoader = MockManifestLoader()
    private var projectDescriptionHelpersHasher = MockProjectDescriptionHelpersHasher()
    private var helpersDirectoryLocator = MockHelpersDirectoryLocator()
    private var cacheDirectoriesProvider: MockCacheDirectoriesProvider!
    private var cacheDirectoriesProviderFactory: MockCacheDirectoriesProviderFactory!
    private var workspaceManifests: [AbsolutePath: Workspace] = [:]
    private var projectManifests: [AbsolutePath: Project] = [:]
    private var configManifests: [AbsolutePath: Config] = [:]
    private var pluginManifests: [AbsolutePath: Plugin] = [:]
    private var recordedLoadWorkspaceCalls: Int = 0
    private var recordedLoadProjectCalls: Int = 0
    private var recordedLoadConfigCalls: Int = 0
    private var recordedLoadPluginCalls: Int = 0

    private var subject: CachedManifestLoader!

    override func setUp() {
        super.setUp()

        do {
            cacheDirectoriesProvider = try MockCacheDirectoriesProvider()
            cacheDirectory = try temporaryPath().appending(components: "tuist", "Cache", "Manifests")
            cacheDirectoriesProviderFactory = MockCacheDirectoriesProviderFactory(provider: cacheDirectoriesProvider)
            cacheDirectoriesProvider.cacheDirectoryStub = cacheDirectory.parentDirectory
        } catch {
            XCTFail("Failed to create temporary directory")
        }

        subject = createSubject()

        manifestLoader.loadWorkspaceStub = { [unowned self] path in
            guard let manifest = self.workspaceManifests[path] else {
                throw ManifestLoaderError.manifestNotFound(.workspace, path)
            }
            self.recordedLoadWorkspaceCalls += 1
            return manifest
        }

        manifestLoader.loadProjectStub = { [unowned self] path in
            guard let manifest = self.projectManifests[path] else {
                throw ManifestLoaderError.manifestNotFound(.project, path)
            }
            self.recordedLoadProjectCalls += 1
            return manifest
        }

        manifestLoader.loadConfigStub = { [unowned self] path in
            guard let manifest = self.configManifests[path] else {
                throw ManifestLoaderError.manifestNotFound(.config, path)
            }
            self.recordedLoadConfigCalls += 1
            return manifest
        }

        manifestLoader.loadPluginStub = { [unowned self] path in
            guard let manifest = self.pluginManifests[path] else {
                throw ManifestLoaderError.manifestNotFound(.plugin, path)
            }
            self.recordedLoadPluginCalls += 1
            return manifest
        }
    }

    override func tearDown() {
        subject = nil
        cacheDirectory = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_load_manifestNotCached() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)

        // When
        let result = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, project)
        XCTAssertEqual(result.name, "App")
    }

    func test_load_manifestCached() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)

        // When
        _ = try subject.loadProject(at: path)
        _ = try subject.loadProject(at: path)
        _ = try subject.loadProject(at: path)
        let result = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, project)
        XCTAssertEqual(recordedLoadProjectCalls, 1)
    }

    func test_load_manifestHashChanged() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let originalProject = Project.test(name: "Original")
        try stubProject(originalProject, at: path)
        _ = try subject.loadProject(at: path)

        // When
        let modifiedProject = Project.test(name: "Modified")
        try stubProject(modifiedProject, at: path)
        let result = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, modifiedProject)
        XCTAssertEqual(result.name, "Modified")
    }

    func test_load_helpersHashChanged() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        try stubHelpers(withHash: "hash")

        _ = try subject.loadProject(at: path)

        // When
        try stubHelpers(withHash: "updatedHash")
        subject = createSubject() // we need to re-create the subject as it internally caches hashes
        _ = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_pluginsHashChanged() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        try stubPlugins(withHash: "hash")

        _ = try subject.loadProject(at: path)

        // When
        try stubPlugins(withHash: "updatedHash")
        subject = createSubject() // we need to re-create the subject as it internally caches hashes
        _ = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_environmentVariablesRemainTheSame() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        environment.manifestLoadingVariables = ["NAME": "A"]

        // When
        _ = try subject.loadProject(at: path)
        _ = try subject.loadProject(at: path)
        _ = try subject.loadProject(at: path)
        let result = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, project)
        XCTAssertEqual(recordedLoadProjectCalls, 1)
    }

    func test_load_environmentVariablesChange() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        environment.manifestLoadingVariables = ["NAME": "A"]
        _ = try subject.loadProject(at: path)

        // When
        environment.manifestLoadingVariables = ["NAME": "B"]
        _ = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_tuistVersionRemainsTheSame() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        subject = createSubject(tuistVersion: "1.0")
        _ = try subject.loadProject(at: path)

        // When
        subject = createSubject(tuistVersion: "1.0")
        _ = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 1)
    }

    func test_load_tuistVersionChanged() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        subject = createSubject(tuistVersion: "1.0")
        _ = try subject.loadProject(at: path)

        // When
        subject = createSubject(tuistVersion: "2.0")
        _ = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_corruptedCache() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stubProject(project, at: path)
        _ = try subject.loadProject(at: path)

        // When
        try corruptFiles(at: cacheDirectory)
        let result = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, project)
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_missingManifest() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadProject(at: path),
            ManifestLoaderError.manifestNotFound(.project, path)
        )
    }

    func test_validate_projectExists() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")

        // When
        manifestLoader.manifestsAtStub = { _ in [.project] }

        // Then
        try subject.validateHasProjectOrWorkspaceManifest(at: path)
    }

    func test_validate_workspaceExists() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")

        // When
        manifestLoader.manifestsAtStub = { _ in [.workspace] }

        // Then
        try subject.validateHasProjectOrWorkspaceManifest(at: path)
    }

    func test_validate_manifestDoesNotExist() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.validateHasProjectOrWorkspaceManifest(at: path),
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
        deprecatedManifest manifest: Config,
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
        let plugin = Plugin(name: "TestPlugin")
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
