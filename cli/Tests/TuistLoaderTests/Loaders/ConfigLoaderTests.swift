import Foundation
import Mockable
import Path
import ProjectDescription
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistTesting

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

        // When
        let result = try await subject.loadConfig(path: configPath)

        // Then

        XCTAssertBetterEqual(result, TuistCore.Tuist(
            project: .generated(TuistGeneratedProjectOptions(
                compatibleXcodeVersions: .all,
                swiftVersion: nil,
                plugins: [],
                generationOptions: .test(),
                installOptions: .test(),
                cacheOptions: .test()
            )),
            fullHandle: nil,
            inspectOptions: .test(),
            url: Constants.URLs.production
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
        XCTAssertEqual(result, TuistCore.Tuist(
            project: .generated(TuistGeneratedProjectOptions(
                compatibleXcodeVersions: .all,
                swiftVersion: nil,
                plugins: [],
                generationOptions: .test(),
                installOptions: .test(),
                cacheOptions: .test()
            )),
            fullHandle: nil,
            inspectOptions: .test(),
            url: Constants.URLs.production
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

    func test_loadConfig_invalid_default_cache_profile_throws() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        let configPath = projectPath.appending(components: Constants.tuistManifestFileName)
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        try await fileSystem.touch(configPath)
        stub(path: configPath, exists: true)
        let invalidProfiles = CacheProfiles.profiles(
            [
                "development": .profile(.allPossible, and: ["tag:cacheable"]),
            ],
            default: "missing"
        )
        stub(
            config: ProjectDescription.Config(project: .tuist(cacheOptions: .options(
                keepSourceTargets: false,
                profiles: invalidProfiles
            ))),
            at: configPath.parentDirectory
        )
        stub(rootDirectory: projectPath)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.loadConfig(path: configPath),
            CacheOptionsManifestMapperError.defaultCacheProfileNotFound(profile: "missing", available: ["development"])
        )
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
        XCTAssertEqual(result, TuistCore.Tuist(
            project: .generated(TuistGeneratedProjectOptions(
                compatibleXcodeVersions: .all,
                swiftVersion: nil,
                plugins: [],
                generationOptions: .test(),
                installOptions: .test(),
                cacheOptions: .test()
            )),
            fullHandle: nil,
            inspectOptions: .test(),
            url: Constants.URLs.production
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
        XCTAssertBetterEqual(result, TuistCore.Tuist(
            project: .generated(TuistGeneratedProjectOptions(
                compatibleXcodeVersions: .all,
                swiftVersion: nil,
                plugins: [],
                generationOptions: .test(
                    buildInsightsDisabled: false,
                    testInsightsDisabled: false
                ),
                installOptions: .test(),
                cacheOptions: .test()
            )),
            fullHandle: "tuist/tuist",
            inspectOptions: .test(),
            url: try XCTUnwrap(URL(string: "https://test.tuist.io"))
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
            config: ProjectDescription.Config(fullHandle: "tuist/tuist", url: "https://test.tuist.io", project: .tuist()),
            at: configPath.parentDirectory
        )

        // When
        let result = try await subject.loadConfig(path: projectPath)

        // Then
        XCTAssertBetterEqual(result, TuistCore.Tuist(
            project: .generated(TuistGeneratedProjectOptions(
                compatibleXcodeVersions: .all,
                swiftVersion: nil,
                plugins: [],
                generationOptions: .test(
                    buildInsightsDisabled: false,
                    testInsightsDisabled: false
                ),
                installOptions: .test(),
                cacheOptions: .test()
            )),
            fullHandle: "tuist/tuist",
            inspectOptions: .test(),
            url: try XCTUnwrap(URL(string: "https://test.tuist.io"))
        ))
    }

    func test_loadConfig_whenFileIsMissing_but_xcodeProjectIsPresent() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        try await fileSystem.makeDirectory(at: projectPath)
        try await fileSystem.touch(projectPath.appending(component: "Test.xcodeproj"))
        stub(rootDirectory: nil)

        // When
        let result = try await subject.loadConfig(path: projectPath)

        // Then
        XCTAssertBetterEqual(result, TuistCore.Tuist(
            project: .xcode(TuistXcodeProjectOptions()),
            fullHandle: nil,
            inspectOptions: .test(),
            url: Constants.URLs.production
        ))
    }

    func test_loadConfig_whenFileIsMissing_but_xcodeWorkspaceIsPresent() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        try await fileSystem.makeDirectory(at: projectPath)
        try await fileSystem.touch(projectPath.appending(component: "Test.xcworkspace"))
        stub(rootDirectory: nil)

        // When
        let result = try await subject.loadConfig(path: projectPath)

        // Then
        XCTAssertBetterEqual(result, TuistCore.Tuist(
            project: .xcode(TuistXcodeProjectOptions()),
            fullHandle: nil,
            inspectOptions: .test(),
            url: Constants.URLs.production
        ))
    }

    func test_loadConfig_whenFileIsMissing_but_swiftPackageExists() async throws {
        // Given
        let packageDirectoryPath = try temporaryPath().appending(component: "package")
        try await fileSystem.makeDirectory(at: packageDirectoryPath)
        try await fileSystem.touch(packageDirectoryPath.appending(component: "Package.swift"))
        stub(rootDirectory: nil)

        // When
        let result = try await subject.loadConfig(path: packageDirectoryPath)

        // Then
        XCTAssertBetterEqual(result, TuistCore.Tuist(
            project: .swiftPackage(TuistSwiftPackageOptions()),
            fullHandle: nil,
            inspectOptions: .test(),
            url: Constants.URLs.production
        ))
    }

    func test_loadConfig_whenFileIsMissing_and_generatedWorkspaceExists() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        try await fileSystem.makeDirectory(at: projectPath)
        try await fileSystem.touch(projectPath.appending(component: "Workspace.swift"))
        try await fileSystem.touch(projectPath.appending(component: "Test.xcworkspace"))
        stub(rootDirectory: nil)

        // When
        let result = try await subject.loadConfig(path: projectPath)

        // Then
        XCTAssertBetterEqual(result, TuistCore.Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: nil,
            inspectOptions: .test(),
            url: Constants.URLs.production
        ))
    }

    func test_loadConfig_whenFileIsMissing_and_generatedProjectExists() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "project")
        try await fileSystem.makeDirectory(at: projectPath)
        try await fileSystem.touch(projectPath.appending(component: "Project.swift"))
        try await fileSystem.touch(projectPath.appending(component: "Project.xcodeproj"))
        stub(rootDirectory: nil)

        // When
        let result = try await subject.loadConfig(path: projectPath)

        // Then
        XCTAssertBetterEqual(result, TuistCore.Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: nil,
            inspectOptions: .test(),
            url: Constants.URLs.production
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

    private func stub(rootDirectory: AbsolutePath?) {
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(rootDirectory as AbsolutePath?)
    }

    private enum TestError: Error, Equatable {
        case testError
    }
}
