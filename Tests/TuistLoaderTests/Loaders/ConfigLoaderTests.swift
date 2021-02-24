import Foundation
import ProjectDescription
import TSCBasic
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class ConfigLoaderTests: TuistUnitTestCase {
    private var rootDirectoryLocator = MockRootDirectoryLocator()
    private var manifestLoader = MockManifestLoader()
    private var subject: ConfigLoader!
    private var registeredPaths: [AbsolutePath: Bool] = [:]
    private var registeredConfigs: [AbsolutePath: Result<ProjectDescription.Config, Error>] = [:]

    override func setUp() {
        super.setUp()
        subject = ConfigLoader(
            manifestLoader: manifestLoader,
            rootDirectoryLocator: rootDirectoryLocator,
            fileHandler: fileHandler
        )
        fileHandler.stubExists = { [weak self] path in
            self?.registeredPaths[path] == true
        }
        manifestLoader.loadConfigStub = { [weak self] path in
            guard let self = self,
                let config = self.registeredConfigs[path]
            else {
                throw ManifestLoaderError.manifestNotFound(.config, path)
            }
            return try config.get()
        }
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
        manifestLoader.loadConfigStub = nil
        fileHandler.stubExists = nil
    }

    // MARK: - Tests

    func test_loadConfig_defaultReturnedWhenPathDoesNotExist() throws {
        // Given
        let path: AbsolutePath = "/some/random/path"
        stub(path: path, exists: false)

        // When
        let result = try subject.loadConfig(path: path)

        // Then
        XCTAssertEqual(result, .default)
    }

    func test_loadConfig_loadTuistConfig() throws {
        // Given
        let path: AbsolutePath = "/project/Tuist/Config.swift"
        stub(path: path, exists: true)
        stub(
            config: .test(
                generationOptions: [.developmentRegion("fr")]
            ),
            at: path.parentDirectory
        )

        // When
        let result = try subject.loadConfig(path: path)

        // Then
        XCTAssertEqual(result, TuistGraph.Config(
            compatibleXcodeVersions: .all,
            cloud: nil,
            cache: nil,
            plugins: [],
            generationOptions: [.developmentRegion("fr")],
            path: path
        ))
    }

    func test_loadConfig_loadTuistConfigError() throws {
        // Given
        let path: AbsolutePath = "/project/Tuist/Config.swift"
        stub(path: path, exists: true)
        stub(configError: TestError.testError, at: "/project/Tuist")

        // When / Then
        XCTAssertThrowsSpecific(try subject.loadConfig(path: path), TestError.testError)
    }

    func test_loadConfig_loadTuistConfigInRootDirectory() throws {
        // Given
        stub(rootDirectory: "/project")
        let paths: [AbsolutePath] = [
            "/project/Tuist/Config.swift",
            "/project/Module/",
            "/project/Module/A/",
        ]
        paths.forEach {
            stub(path: $0, exists: true)
        }
        stub(
            config: .test(
                generationOptions: [.developmentRegion("fr")]
            ),
            at: "/project/Tuist"
        )

        // When
        let result = try subject.loadConfig(path: "/project/Module/A/")

        // Then
        XCTAssertEqual(result, TuistGraph.Config(
            compatibleXcodeVersions: .all,
            cloud: nil,
            cache: nil,
            plugins: [],
            generationOptions: [.developmentRegion("fr")],
            path: "/project/Tuist/Config.swift"
        ))
    }

    // MARK: - Helpers

    private func stub(path: AbsolutePath, exists: Bool) {
        registeredPaths[path] = exists
    }

    private func stub(configError: Error, at path: AbsolutePath) {
        registeredConfigs[path] = .failure(configError)
    }

    private func stub(config: ProjectDescription.Config, at path: AbsolutePath) {
        registeredConfigs[path] = .success(config)
    }

    private func stub(rootDirectory: AbsolutePath) {
        rootDirectoryLocator.locateStub = rootDirectory
    }

    private enum TestError: Error, Equatable {
        case testError
    }
}
