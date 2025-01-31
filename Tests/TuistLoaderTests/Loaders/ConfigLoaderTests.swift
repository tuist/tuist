import Foundation
import Mockable
import Path
import ProjectDescription
import TuistCore
import TuistSupport
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
            fileSystem: fileSystem
        )
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

    func test_loadConfig_loadConfig_and_showsAWarning_when_usingConfigSwiftConvention() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        let configPath = projectPath.appending(components: "Tuist", "Config.swift")
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        try await fileSystem.touch(configPath)
        stub(path: configPath, exists: true)
        stub(
            config: .test(),
            at: configPath.parentDirectory
        )
        stub(rootDirectory: projectPath)
        // given(warningController)
        //     .append(
        //         warning: .value(
        //             "Tuist/Config.swift is deprecated. Rename Tuist/Config.swift to \(Constants.tuistManifestFileName) at the
        //             root."
        //         )
        //     )
        //     .willReturn()

        // When
        let result = try await subject.loadConfig(path: configPath)

        // Then
        XCTAssertEqual(result, TuistCore.Config(
            compatibleXcodeVersions: .all,
            fullHandle: nil,
            url: Constants.URLs.production,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .test(),
            installOptions: .test(),
            path: configPath
        ))
    }

    func test_loadConfig_loadConfig() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        try await fileSystem.touch(configPath)
        stub(path: configPath, exists: true)
        stub(
            config: .test(),
            at: configPath.parentDirectory
        )
        stub(rootDirectory: projectPath)

        // When
        let result = try await subject.loadConfig(path: configPath)

        // Then
        XCTAssertEqual(result, TuistCore.Config(
            compatibleXcodeVersions: .all,
            fullHandle: nil,
            url: Constants.URLs.production,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .test(),
            installOptions: .test(),
            path: configPath
        ))
    }

    func test_loadConfig_loadConfigError() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        try await fileSystem.touch(configPath)
        stub(path: configPath, exists: true)
        stub(configError: TestError.testError, at: configPath.parentDirectory)
        stub(rootDirectory: projectPath)

        // When / Then
        await XCTAssertThrowsSpecific({ try await self.subject.loadConfig(path: configPath) }, TestError.testError)
    }

    func test_loadConfig_loadConfigInRootDirectory() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        try await fileSystem.touch(configPath)
        stub(rootDirectory: projectPath)
        let moduleAPath = projectPath.appending(components: "Module", "A")
        try await fileSystem.makeDirectory(at: moduleAPath)
        stub(
            config: .test(),
            at: configPath.parentDirectory
        )

        // When
        let result = try await subject.loadConfig(path: moduleAPath)

        // Then
        XCTAssertEqual(result, TuistCore.Config(
            compatibleXcodeVersions: .all,
            fullHandle: nil,
            url: Constants.URLs.production,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .test(),
            installOptions: .test(),
            path: configPath
        ))
    }

    func test_loadConfig_with_full_handle_and_url() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        try await fileSystem.touch(configPath)
        stub(rootDirectory: projectPath)
        stub(
            config: .test(
                fullHandle: "tuist/tuist",
                url: "https://test.tuist.io"
            ),
            at: configPath.parentDirectory
        )

        // When
        let result = try await subject.loadConfig(path: projectPath)

        // Then
        XCTAssertBetterEqual(result, TuistCore.Config(
            compatibleXcodeVersions: .all,
            fullHandle: "tuist/tuist",
            url: try XCTUnwrap(URL(string: "https://test.tuist.io")),
            swiftVersion: nil,
            plugins: [],
            generationOptions: .test(),
            installOptions: .test(),
            path: configPath
        ))
    }

    func test_loadConfig_with_deprecated_cloud() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        try await fileSystem.touch(configPath)
        stub(rootDirectory: projectPath)
        stub(
            config: ProjectDescription.Config(
                cloud: .cloud(
                    projectId: "tuist/tuist",
                    url: "https://test.tuist.io"
                )
            ),
            at: configPath.parentDirectory
        )

        // When
        let result = try await subject.loadConfig(path: projectPath)

        // Then
        XCTAssertBetterEqual(result, TuistCore.Config(
            compatibleXcodeVersions: .all,
            fullHandle: "tuist/tuist",
            url: try XCTUnwrap(URL(string: "https://test.tuist.io")),
            swiftVersion: nil,
            plugins: [],
            generationOptions: .test(),
            installOptions: .test(),
            path: configPath
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
            .willReturn(rootDirectory as AbsolutePath?)
    }

    private enum TestError: Error, Equatable {
        case testError
    }
}
