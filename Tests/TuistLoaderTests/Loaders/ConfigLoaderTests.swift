import Foundation
import MockableTest
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class ConfigLoaderTests: TuistUnitTestCase {
    private var rootDirectoryLocator: MockRootDirectoryLocating!
    private var manifestLoader: MockManifestLoading!
    private var subject: ConfigLoader!
    private var registeredPaths: [AbsolutePath: Bool] = [:]
    private var registeredConfigs: [AbsolutePath: Result<ProjectDescription.Config, Error>] = [:]

    override func setUp() {
        super.setUp()
        rootDirectoryLocator = .init()
        manifestLoader = .init()
        subject = ConfigLoader(
            manifestLoader: manifestLoader,
            rootDirectoryLocator: rootDirectoryLocator,
            fileHandler: fileHandler
        )
        fileHandler.stubExists = { [weak self] path in
            self?.registeredPaths[path] == true
        }
        given(manifestLoader)
            .loadConfig(at: .any)
            .willProduce { [weak self] path in
                guard let self,
                      let config = registeredConfigs[path]
                else {
                    throw ManifestLoaderError.manifestNotFound(.config, path)
                }
                return try config.get()
            }
    }

    override func tearDown() {
        subject = nil
        manifestLoader = nil
        fileHandler.stubExists = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_loadConfig_defaultReturnedWhenPathDoesNotExist() async throws {
        // Given
        let path: AbsolutePath = "/some/random/path"
        stub(path: path, exists: false)
        stub(rootDirectory: "/project")

        // When
        let result = try await subject.loadConfig(path: path)

        // Then
        XCTAssertEqual(result, .default)
    }

    func test_loadConfig_loadConfig() async throws {
        // Given
        let path: AbsolutePath = "/project/Tuist/Config.swift"
        stub(path: path, exists: true)
        stub(
            config: .test(),
            at: path.parentDirectory
        )
        stub(rootDirectory: "/project")

        // When
        let result = try await subject.loadConfig(path: path)

        // Then
        XCTAssertEqual(result, TuistCore.Config(
            compatibleXcodeVersions: .all,
            fullHandle: nil,
            url: Constants.URLs.production,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .test(),
            path: path
        ))
    }

    func test_loadConfig_loadConfigError() async throws {
        // Given
        let path: AbsolutePath = "/project/Tuist/Config.swift"
        stub(path: path, exists: true)
        stub(configError: TestError.testError, at: "/project/Tuist")
        stub(rootDirectory: "/project")

        // When / Then
        await XCTAssertThrowsSpecific({ try await self.subject.loadConfig(path: path) }, TestError.testError)
    }

    func test_loadConfig_loadConfigInRootDirectory() async throws {
        // Given
        stub(rootDirectory: "/project")
        let paths: [AbsolutePath] = [
            "/project/Tuist/Config.swift",
            "/project/Module/",
            "/project/Module/A/",
        ]
        for item in paths {
            stub(path: item, exists: true)
        }
        stub(
            config: .test(),
            at: "/project/Tuist"
        )

        // When
        let result = try await subject.loadConfig(path: "/project/Module/A/")

        // Then
        XCTAssertEqual(result, TuistCore.Config(
            compatibleXcodeVersions: .all,
            fullHandle: nil,
            url: Constants.URLs.production,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .test(),
            path: "/project/Tuist/Config.swift"
        ))
    }

    func test_loadConfig_with_full_handle_and_url() async throws {
        // Given
        stub(rootDirectory: "/project")
        stub(path: "/project/Tuist/Config.swift", exists: true)
        stub(
            config: .test(
                fullHandle: "tuist/tuist",
                url: "https://test.tuist.io"
            ),
            at: "/project/Tuist"
        )

        // When
        let result = try await subject.loadConfig(path: "/project")

        // Then
        XCTAssertBetterEqual(result, TuistCore.Config(
            compatibleXcodeVersions: .all,
            fullHandle: "tuist/tuist",
            url: try XCTUnwrap(URL(string: "https://test.tuist.io")),
            swiftVersion: nil,
            plugins: [],
            generationOptions: .test(),
            path: "/project/Tuist/Config.swift"
        ))
    }

    func test_loadConfig_with_deprecated_cloud() async throws {
        // Given
        stub(rootDirectory: "/project")
        stub(path: "/project/Tuist/Config.swift", exists: true)
        stub(
            config: ProjectDescription.Config(
                cloud: .cloud(
                    projectId: "tuist/tuist",
                    url: "https://test.tuist.io"
                )
            ),
            at: "/project/Tuist"
        )

        // When
        let result = try await subject.loadConfig(path: "/project")

        // Then
        XCTAssertBetterEqual(result, TuistCore.Config(
            compatibleXcodeVersions: .all,
            fullHandle: "tuist/tuist",
            url: try XCTUnwrap(URL(string: "https://test.tuist.io")),
            swiftVersion: nil,
            plugins: [],
            generationOptions: .test(),
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
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(rootDirectory)
    }

    private enum TestError: Error, Equatable {
        case testError
    }
}
