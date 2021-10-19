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
        subject = PluginService(
            manifestLoader: manifestLoader,
            templatesDirectoryLocator: templatesDirectoryLocator,
            fileHandler: fileHandler,
            gitHandler: gitHandler,
            cacheDirectoryProviderFactory: cacheDirectoryProviderFactory
        )
    }

    override func tearDown() {
        manifestLoader = nil
        templatesDirectoryLocator = nil
        gitHandler = nil
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
                .git(url: pluginAGitURL, gitID: .sha(pluginAGitSha)),
                .git(url: pluginBGitURL, gitID: .tag(pluginBGitTag)),
                .git(url: pluginCGitURL, gitID: .tag(pluginCGitTag)),
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
            .sorted(by: { $0.repositoryPath > $1.repositoryPath })
        
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
    
    func test_fetchRemotePlugins_when_git_sha() throws {
        // Given
        let pluginGitURL = "https://url/to/repo.git"
        let pluginGitSha = "abc"
        let pluginFingerprint = "\(pluginGitURL)-\(pluginGitSha)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginGitURL, gitID: .sha(pluginGitSha))
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
        try subject.fetchRemotePlugins(using: config)
        
        // Then
        XCTAssertEqual(invokedCloneURL, pluginGitURL)
        XCTAssertEqual(
            invokedClonePath,
            cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
        XCTAssertEqual(invokedCheckoutID, pluginGitSha)
        XCTAssertEqual(
            invokedCheckoutPath,
            cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
    }
    
    func test_fetchRemotePlugins_when_git_tag_and_repository_not_cached() throws {
        // Given
        let pluginGitURL = "https://url/to/repo.git"
        let pluginGitTag = "1.0.0"
        let pluginFingerprint = "\(pluginGitURL)-\(pluginGitTag)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginGitURL, gitID: .tag(pluginGitTag))
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
        try subject.fetchRemotePlugins(using: config)
        
        // Then
        XCTAssertEqual(invokedCloneURL, pluginGitURL)
        XCTAssertEqual(
            invokedClonePath,
            cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
        XCTAssertEqual(invokedCheckoutID, pluginGitTag)
        XCTAssertEqual(
            invokedCheckoutPath,
            cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
    }
    
    func test_fetchRemotePlugins_when_git_tag_and_repository_cached() throws {
        // Given
        let pluginGitURL = "https://url/to/repo.git"
        let pluginGitTag = "1.0.0"
        let pluginFingerprint = "\(pluginGitURL)-\(pluginGitTag)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginGitURL, gitID: .tag(pluginGitTag))
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
        let downloadPath = temporaryDirectory.appending(component: "release.zip")
        system.succeedCommand(
            "/usr/bin/curl", "-LSs", "--output",
            downloadPath.pathString,
            "\(pluginGitURL)/releases/download/\(pluginGitTag)/Plugin.tuist-plugin.zip"
        )
        system.succeedCommand(
            "/usr/bin/unzip",
            "-q", downloadPath.pathString,
            "-d", pluginDirectory.appending(component: PluginServiceConstants.release).pathString
        )
        let commandPath = pluginDirectory.appending(components: PluginServiceConstants.release, "tuist-command")
        try fileHandler.touch(commandPath)
        system.succeedCommand("/bin/chmod", "+x", commandPath.pathString)
        
        // When
        try subject.fetchRemotePlugins(using: config)
        
        // Then
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
        let expectedPlugins = Plugins.test(projectDescriptionHelpers: [.init(name: pluginName, path: expectedHelpersPath, location: .local)])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_WHEN_gitHelpers() throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitId = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitId)".md5
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint, PluginServiceConstants.repository)
        let pluginName = "TestPlugin"

        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitId)])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        try fileHandler.createFolder(cachedPluginPath.appending(component: Constants.helpersDirectoryName))

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.git(url: pluginGitUrl, gitID: .tag(pluginGitId))])

        // When
        let plugins = try subject.loadPlugins(using: config)

        // Then
        let expectedHelpersPath = cachedPluginPath.appending(component: Constants.helpersDirectoryName)
        let expectedPlugins = Plugins.test(projectDescriptionHelpers: [.init(name: pluginName, path: expectedHelpersPath, location: .remote)])
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
        let pluginGitId = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitId)".md5
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint, PluginServiceConstants.repository)
        let pluginName = "TestPlugin"
        let resourceTemplatesPath = cachedPluginPath.appending(components: "ResourceSynthesizers")

        try makeDirectories(resourceTemplatesPath)

        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitId)])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.git(url: pluginGitUrl, gitID: .tag(pluginGitId))])

        // When
        let plugins = try subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(
            resourceSynthesizers: [
                PluginResourceSynthesizer(name: pluginName, path: resourceTemplatesPath),
            ]
        )
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_WHEN_localTasks() throws {
        // Given
        let pluginPath = try temporaryPath()
        let pluginName = "TestPlugin"
        let tasksPath = pluginPath.appending(components: Constants.tasksDirectoryName)

        try makeDirectories(tasksPath)

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
        let expectedPlugins = Plugins.test(
            tasks: [
                PluginTasks(name: pluginName, path: tasksPath),
            ]
        )
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_WHEN_gitTasks() throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitId = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitId)".md5
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint, PluginServiceConstants.repository)
        let pluginName = "TestPlugin"
        let tasksPath = cachedPluginPath.appending(components: Constants.tasksDirectoryName)

        try makeDirectories(tasksPath)

        // When
        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitId)])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.git(url: pluginGitUrl, gitID: .tag(pluginGitId))])

        // Then
        let plugins = try subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(
            tasks: [
                PluginTasks(name: pluginName, path: tasksPath),
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
        let pluginGitId = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitId)".md5
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint, PluginServiceConstants.repository)
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
            .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitId)])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.git(url: pluginGitUrl, gitID: .tag(pluginGitId))])

        // Then
        let plugins = try subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(templatePaths: [templatePath])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_cacheConfiguration_WHEN_loadPlugin() throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitId = "1.0.0"
        let config = mockConfig(plugins: [TuistGraph.PluginLocation.git(url: pluginGitUrl, gitID: .tag(pluginGitId))])

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
            generationOptions: [],
            path: nil
        )
    }
}
