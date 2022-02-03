import ProjectDescription
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistLoader
import TuistLoaderTesting
import TuistScaffold
import TuistScaffoldTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistPlugin

final class PluginServiceTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoader!
    private var templatesDirectoryLocator: MockTemplatesDirectoryLocator!
    private var gitHandler: MockGitHandler!
    private var subject: PluginService!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProvider!
    private var cacheDirectoryProviderFactory: MockCacheDirectoriesProviderFactory!
    private var fileUnarchiver: MockFileUnarchiver!
    private var fileClient: MockFileClient!

    override func setUp() {
        super.setUp()
        manifestLoader = MockManifestLoader()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        gitHandler = MockGitHandler()
        let mockCacheDirectoriesProvider = try! MockCacheDirectoriesProvider()
        cacheDirectoriesProvider = mockCacheDirectoriesProvider
        cacheDirectoriesProvider.cacheDirectoryStub = try! temporaryPath()
        cacheDirectoryProviderFactory = MockCacheDirectoriesProviderFactory(provider: cacheDirectoriesProvider)
        cacheDirectoryProviderFactory.cacheDirectoriesStub = { _ in mockCacheDirectoriesProvider }
        fileUnarchiver = MockFileUnarchiver()
        let fileArchivingFactory = MockFileArchivingFactory()
        fileArchivingFactory.stubbedMakeFileUnarchiverResult = fileUnarchiver
        fileClient = MockFileClient()
        subject = PluginService(
            manifestLoader: manifestLoader,
            templatesDirectoryLocator: templatesDirectoryLocator,
            fileHandler: fileHandler,
            gitHandler: gitHandler,
            cacheDirectoryProviderFactory: cacheDirectoryProviderFactory,
            fileArchivingFactory: fileArchivingFactory,
            fileClient: fileClient
        )
    }

    override func tearDown() {
        manifestLoader = nil
        templatesDirectoryLocator = nil
        gitHandler = nil
        cacheDirectoriesProvider = nil
        cacheDirectoryProviderFactory = nil
        fileUnarchiver = nil
        fileClient = nil
        subject = nil
        super.tearDown()
    }

    func test_remotePluginPaths() throws {
        // Given
        let pluginAGitURL = "https://url/to/repo/a.git"
        let pluginAGitSha = "abc"
        let pluginAFingerprint = "\(pluginAGitURL)-\(pluginAGitSha)".md5
        let pluginBGitURL = "https://url/to/repo/b.git"
        let pluginBGitTag = "abc"
        let pluginBFingerprint = "\(pluginBGitURL)-\(pluginBGitTag)".md5
        let pluginCGitURL = "https://url/to/repo/c.git"
        let pluginCGitTag = "abc"
        let pluginCFingerprint = "\(pluginCGitURL)-\(pluginCGitTag)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginAGitURL, gitReference: .sha(pluginAGitSha)),
                .git(url: pluginBGitURL, gitReference: .tag(pluginBGitTag)),
                .git(url: pluginCGitURL, gitReference: .tag(pluginCGitTag)),
            ]
        )
        let pluginADirectory = cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(component: pluginAFingerprint)
        let pluginBDirectory = cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(component: pluginBFingerprint)
        let pluginCDirectory = cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(component: pluginCFingerprint)
        try fileHandler.touch(
            pluginBDirectory.appending(components: PluginServiceConstants.release)
        )

        // When
        let remotePluginPaths = try subject.remotePluginPaths(using: config)

        // Then
        XCTAssertEqual(
            Set(remotePluginPaths),
            Set([
                RemotePluginPaths(
                    repositoryPath: pluginADirectory.appending(component: PluginServiceConstants.repository),
                    releasePath: nil
                ),
                RemotePluginPaths(
                    repositoryPath: pluginBDirectory.appending(component: PluginServiceConstants.repository),
                    releasePath: pluginBDirectory.appending(component: PluginServiceConstants.release)
                ),
                RemotePluginPaths(
                    repositoryPath: pluginCDirectory.appending(component: PluginServiceConstants.repository),
                    releasePath: nil
                ),
            ])
        )
    }

    func test_fetchRemotePlugins_when_git_sha() async throws {
        // Given
        let pluginGitURL = "https://url/to/repo.git"
        let pluginGitSha = "abc"
        let pluginFingerprint = "\(pluginGitURL)-\(pluginGitSha)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginGitURL, gitReference: .sha(pluginGitSha)),
            ]
        )
        var invokedCloneURL: String?
        var invokedClonePath: AbsolutePath?
        gitHandler.cloneToStub = { url, path in
            invokedCloneURL = url
            invokedClonePath = path
        }
        var invokedCheckoutID: String?
        var invokedCheckoutPath: AbsolutePath?
        gitHandler.checkoutStub = { id, path in
            invokedCheckoutID = id
            invokedCheckoutPath = path
        }

        // When
        _ = try await subject.fetchRemotePlugins(using: config)

        // Then
        XCTAssertEqual(invokedCloneURL, pluginGitURL)
        XCTAssertEqual(
            invokedClonePath,
            cacheDirectoriesProvider.cacheDirectory(for: .plugins)
                .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
        XCTAssertEqual(invokedCheckoutID, pluginGitSha)
        XCTAssertEqual(
            invokedCheckoutPath,
            cacheDirectoriesProvider.cacheDirectory(for: .plugins)
                .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
    }

    func test_fetchRemotePlugins_when_git_tag_and_repository_not_cached() async throws {
        // Given
        let pluginGitURL = "https://url/to/repo.git"
        let pluginGitTag = "1.0.0"
        let pluginFingerprint = "\(pluginGitURL)-\(pluginGitTag)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginGitURL, gitReference: .tag(pluginGitTag)),
            ]
        )
        var invokedCloneURL: String?
        var invokedClonePath: AbsolutePath?
        gitHandler.cloneToStub = { url, path in
            invokedCloneURL = url
            invokedClonePath = path
        }
        var invokedCheckoutID: String?
        var invokedCheckoutPath: AbsolutePath?
        gitHandler.checkoutStub = { id, path in
            invokedCheckoutID = id
            invokedCheckoutPath = path
        }

        // When
        _ = try await subject.fetchRemotePlugins(using: config)

        // Then
        XCTAssertEqual(invokedCloneURL, pluginGitURL)
        XCTAssertEqual(
            invokedClonePath,
            cacheDirectoriesProvider.cacheDirectory(for: .plugins)
                .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
        XCTAssertEqual(invokedCheckoutID, pluginGitTag)
        XCTAssertEqual(
            invokedCheckoutPath,
            cacheDirectoriesProvider.cacheDirectory(for: .plugins)
                .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
    }

    func test_fetchRemotePlugins_when_git_tag_and_repository_cached() async throws {
        // Given
        let pluginGitURL = "https://url/to/repo.git"
        let pluginGitTag = "1.0.0"
        let pluginFingerprint = "\(pluginGitURL)-\(pluginGitTag)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginGitURL, gitReference: .tag(pluginGitTag)),
            ]
        )

        let pluginDirectory = cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(component: pluginFingerprint)
        let temporaryDirectory = try temporaryPath()
        cacheDirectoriesProvider.cacheDirectoryStub = temporaryDirectory
        try fileHandler.touch(
            pluginDirectory
                .appending(components: PluginServiceConstants.repository, Constants.DependenciesDirectory.packageSwiftName)
        )
        let commandPath = pluginDirectory.appending(components: PluginServiceConstants.release, "tuist-command")
        try fileHandler.touch(commandPath)

        // When / Then
        _ = try await subject.fetchRemotePlugins(using: config)
    }

    func test_loadPlugins_WHEN_localHelpers() throws {
        // Given
        let pluginPath = try temporaryPath().appending(component: "Plugin")
        let pluginName = "TestPlugin"

        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [.local(path: .relativeToRoot(pluginPath.pathString))])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.local(path: pluginPath.pathString)])

        try fileHandler.createFolder(
            pluginPath.appending(component: Constants.helpersDirectoryName)
        )

        // When
        let plugins = try subject.loadPlugins(using: config)

        // Then
        let expectedHelpersPath = pluginPath.appending(component: Constants.helpersDirectoryName)
        let expectedPlugins = Plugins
            .test(projectDescriptionHelpers: [.init(name: pluginName, path: expectedHelpersPath, location: .local)])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_WHEN_gitHelpers() throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitReference = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitReference)".md5
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        let pluginName = "TestPlugin"

        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitReference)])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        try fileHandler.createFolder(cachedPluginPath.appending(component: Constants.helpersDirectoryName))

        let config =
            mockConfig(plugins: [TuistGraph.PluginLocation.git(url: pluginGitUrl, gitReference: .tag(pluginGitReference))])

        // When
        let plugins = try subject.loadPlugins(using: config)

        // Then
        let expectedHelpersPath = cachedPluginPath.appending(component: Constants.helpersDirectoryName)
        let expectedPlugins = Plugins
            .test(projectDescriptionHelpers: [.init(name: pluginName, path: expectedHelpersPath, location: .remote)])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_when_localResourceSynthesizer() throws {
        // Given
        let pluginPath = try temporaryPath()
        let pluginName = "TestPlugin"
        let resourceTemplatesPath = pluginPath.appending(components: "ResourceSynthesizers")

        try makeDirectories(resourceTemplatesPath)

        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [.local(path: .relativeToRoot(pluginPath.pathString))])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.local(path: pluginPath.pathString)])

        // When
        let plugins = try subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(
            resourceSynthesizers: [
                PluginResourceSynthesizer(name: pluginName, path: resourceTemplatesPath),
            ]
        )
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_when_remoteResourceSynthesizer() throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitReference = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitReference)".md5
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        let pluginName = "TestPlugin"
        let resourceTemplatesPath = cachedPluginPath.appending(components: "ResourceSynthesizers")

        try makeDirectories(resourceTemplatesPath)

        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitReference)])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        let config =
            mockConfig(plugins: [TuistGraph.PluginLocation.git(url: pluginGitUrl, gitReference: .tag(pluginGitReference))])

        // When
        let plugins = try subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(
            resourceSynthesizers: [
                PluginResourceSynthesizer(name: pluginName, path: resourceTemplatesPath),
            ]
        )
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_WHEN_localTemplate() throws {
        // Given
        let pluginPath = try temporaryPath()
        let pluginName = "TestPlugin"
        let templatePath = pluginPath.appending(components: "Templates", "custom")
        templatesDirectoryLocator.templatePluginDirectoriesStub = { _ in
            [
                templatePath,
            ]
        }

        try makeDirectories(templatePath)

        // When
        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [.local(path: .relativeToRoot(pluginPath.pathString))])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.local(path: pluginPath.pathString)])

        // Then
        let plugins = try subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(templatePaths: [templatePath])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_WHEN_gitTemplate() throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitReference = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitReference)".md5
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        let pluginName = "TestPlugin"
        let templatePath = cachedPluginPath.appending(components: "Templates", "custom")
        templatesDirectoryLocator.templatePluginDirectoriesStub = { _ in
            [
                templatePath,
            ]
        }

        try makeDirectories(templatePath)

        // When
        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitReference)])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        let config =
            mockConfig(plugins: [TuistGraph.PluginLocation.git(url: pluginGitUrl, gitReference: .tag(pluginGitReference))])

        // Then
        let plugins = try subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(templatePaths: [templatePath])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_cacheConfiguration_WHEN_loadPlugin() throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitReference = "1.0.0"
        let config =
            mockConfig(plugins: [TuistGraph.PluginLocation.git(url: pluginGitUrl, gitReference: .tag(pluginGitReference))])

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadPlugins(using: config),
            PluginServiceError.missingRemotePlugins(["Plugin"])
        )
        XCTAssertEqual(cacheDirectoryProviderFactory.cacheDirectoriesConfig, config)
    }

    private func mockConfig(plugins: [TuistGraph.PluginLocation]) -> TuistGraph.Config {
        Config(
            compatibleXcodeVersions: .all,
            cloud: nil,
            cache: nil,
            swiftVersion: nil,
            plugins: plugins,
            generationOptions: .test(),
            path: nil
        )
    }
}
