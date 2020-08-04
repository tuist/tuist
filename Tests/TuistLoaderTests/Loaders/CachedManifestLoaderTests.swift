import Foundation
import ProjectDescription
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class CachedManifestLoaderTests: TuistUnitTestCase {
    private var cacheDirectory: AbsolutePath!
    private var manifestLoader = MockManifestLoader()
    private var projectDescriptionHelpersHasher = MockProjectDescriptionHelpersHasher()
    private var helpersDirectoryLocator = MockHelpersDirectoryLocator()
    private var projectManifests: [AbsolutePath: Project] = [:]
    private var configManifests: [AbsolutePath: Config] = [:]
    private var recordedLoadProjectCalls: Int = 0
    private var recordedLoadConfigCalls: Int = 0

    private var subject: CachedManifestLoader!

    override func setUp() {
        super.setUp()

        do {
            cacheDirectory = try temporaryPath().appending(components: "tuist", "Cache", "Manifests")
        } catch {
            XCTFail("Failed to create temporary directory")
        }

        subject = createSubject()

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
    }

    override func tearDown() {
        super.tearDown()

        subject = nil
        cacheDirectory = nil
    }

    // MARK: - Tests

    func test_load_manifestNotCached() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stub(manifest: project, at: path)

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
        try stub(manifest: project, at: path)

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
        try stub(manifest: originalProject, at: path)
        _ = try subject.loadProject(at: path)

        // When
        let modifiedProject = Project.test(name: "Modified")
        try stub(manifest: modifiedProject, at: path)
        let result = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(result, modifiedProject)
        XCTAssertEqual(result.name, "Modified")
    }

    func test_load_helpersHashChanged() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stub(manifest: project, at: path)
        try stubHelpers(withHash: "hash")

        _ = try subject.loadProject(at: path)

        // When
        try stubHelpers(withHash: "updatedHash")
        subject = createSubject() // we need to re-create the subject as it internally caches hashes
        _ = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_environmentVariablesRemainTheSame() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stub(manifest: project, at: path)
        environment.tuistVariables = ["NAME": "A"]

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
        try stub(manifest: project, at: path)
        environment.tuistVariables = ["NAME": "A"]
        _ = try subject.loadProject(at: path)

        // When
        environment.tuistVariables = ["NAME": "B"]
        _ = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(recordedLoadProjectCalls, 2)
    }

    func test_load_tuistVersionRemainsTheSame() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let project = Project.test(name: "App")
        try stub(manifest: project, at: path)
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
        try stub(manifest: project, at: path)
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
        try stub(manifest: project, at: path)
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
        XCTAssertThrowsSpecific(try subject.loadProject(at: path),
                                ManifestLoaderError.manifestNotFound(.project, path))
    }

    func test_load_deprecatedFileName() throws {
        // Given
        let path = try temporaryPath().appending(component: "App")
        let config = Config.test(generationOptions: [.organizationName("Foo")])
        try stub(deprecatedManifest: config, at: path)

        // When
        _ = try subject.loadConfig(at: path)
        _ = try subject.loadConfig(at: path)
        let result = try subject.loadConfig(at: path)

        // Then
        XCTAssertEqual(result, config)
        XCTAssertEqual(recordedLoadConfigCalls, 1)
    }

    // MARK: - Helpers

    private func createSubject(tuistVersion: String = "1.0") -> CachedManifestLoader {
        CachedManifestLoader(manifestLoader: manifestLoader,
                             projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
                             helpersDirectoryLocator: helpersDirectoryLocator,
                             cacheDirectory: cacheDirectory,
                             fileHandler: fileHandler,
                             environment: environment,
                             tuistVersion: tuistVersion)
    }

    private func stub(manifest: Project,
                      at path: AbsolutePath) throws
    {
        let manifestPath = path.appending(component: Manifest.project.fileName)
        try fileHandler.touch(manifestPath)
        let manifestData = try JSONEncoder().encode(manifest)
        try fileHandler.write(String(data: manifestData, encoding: .utf8)!, path: manifestPath, atomically: true)
        projectManifests[path] = manifest
    }

    private func stub(deprecatedManifest manifest: Config,
                      at path: AbsolutePath) throws
    {
        let manifestPath = path.appending(component: Manifest.config.deprecatedFileName ?? Manifest.config.fileName)
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

    private func corruptFiles(at path: AbsolutePath) throws {
        for filePath in try fileHandler.contentsOfDirectory(path) {
            try fileHandler.write("corruptedData", path: filePath, atomically: true)
        }
    }
}
