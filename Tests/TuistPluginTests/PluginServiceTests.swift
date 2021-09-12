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

final class PluginServiceTests: TuistTestCase {
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
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint)
        let pluginName = "TestPlugin"

        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitId)])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        try fileHandler.createFolder(cachedPluginPath.appending(component: Constants.helpersDirectoryName))

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.gitWithTag(url: pluginGitUrl, tag: pluginGitId)])

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
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint)
        let pluginName = "TestPlugin"
        let resourceTemplatesPath = cachedPluginPath.appending(components: "ResourceSynthesizers")

        try makeDirectories(resourceTemplatesPath)

        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitId)])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.gitWithTag(url: pluginGitUrl, tag: pluginGitId)])

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
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint)
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

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.gitWithTag(url: pluginGitUrl, tag: pluginGitId)])

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
        let cachedPluginPath = cacheDirectoriesProvider.cacheDirectory(for: .plugins).appending(components: pluginFingerprint)
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

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.gitWithTag(url: pluginGitUrl, tag: pluginGitId)])

        // Then
        let plugins = try subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(templatePaths: [templatePath])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_cacheConfiguration_WHEN_loadPlugin() throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitId = "1.0.0"
        let config = mockConfig(plugins: [TuistGraph.PluginLocation.gitWithTag(url: pluginGitUrl, tag: pluginGitId)])

        // When
        _ = try subject.loadPlugins(using: config)

        // Then
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
