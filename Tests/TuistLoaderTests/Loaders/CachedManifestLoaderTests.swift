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
    private var subject: CachedManifestLoader!
    private var projectManifests: [AbsolutePath: Project] = [:]
    private var recordedLoadProjectCalls: Int = 0

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

    // MARK: - Helpers

    private func createSubject() -> CachedManifestLoader {
        CachedManifestLoader(manifestLoader: manifestLoader,
                             projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
                             helpersDirectoryLocator: helpersDirectoryLocator,
                             cacheDirectory: cacheDirectory,
                             fileHandler: fileHandler)
    }

    private func stub(manifest: Project,
                      at path: AbsolutePath) throws {
        let manifestPath = path.appending(component: Manifest.project.fileName)
        try fileHandler.touch(manifestPath)
        let manifestData = try JSONEncoder().encode(manifest)
        try fileHandler.write(String(data: manifestData, encoding: .utf8)!, path: manifestPath, atomically: true)
        projectManifests[path] = manifest
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
