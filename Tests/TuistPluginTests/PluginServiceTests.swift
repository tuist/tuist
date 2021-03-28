import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistLoader
import TuistLoaderTesting
import TuistSupport
import TuistSupportTesting
import TuistScaffold
import TuistScaffoldTesting
import XCTest

@testable import TuistPlugin

final class PluginServiceTests: TuistTestCase {
    private var manifestLoader: MockManifestLoader!
    private var templatesDirectoryLocator: MockTemplatesDirectoryLocator!
    private var gitHandler: MockGitHandler!
    private var subject: PluginService!

    override func setUp() {
        super.setUp()
        manifestLoader = MockManifestLoader()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        gitHandler = MockGitHandler()
        subject = PluginService(
            manifestLoader: manifestLoader,
            templatesDirectoryLocator: templatesDirectoryLocator,
            fileHandler: fileHandler,
            gitHandler: gitHandler
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
        let pluginPath = AbsolutePath("/path/to/Plugin")
        let pluginName = "TestPlugin"

        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [.local(path: .relativeToRoot(pluginPath.pathString))])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        fileHandler.stubExists = { _ in
            true
        }

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.local(path: pluginPath.pathString)])
        let plugins = try subject.loadPlugins(using: config)
        let expectedHelpersPath = pluginPath.appending(component: Constants.helpersDirectoryName)
        let expectedPlugins = Plugins.test(projectDescriptionHelpers: [.init(name: pluginName, path: expectedHelpersPath, location: .local)])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_WHEN_gitHelpers() throws {
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitId = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitId)".md5
        let cachedPluginPath = environment.cacheDirectory.appending(components: Constants.pluginsDirectoryName, pluginFingerprint)
        let pluginName = "TestPlugin"

        manifestLoader.loadConfigStub = { _ in
            .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitId)])
        }

        manifestLoader.loadPluginStub = { _ in
            ProjectDescription.Plugin(name: pluginName)
        }

        fileHandler.stubExists = { _ in
            true
        }

        let config = mockConfig(plugins: [TuistGraph.PluginLocation.gitWithTag(url: pluginGitUrl, tag: pluginGitId)])
        let plugins = try subject.loadPlugins(using: config)
        let expectedHelpersPath = cachedPluginPath.appending(component: Constants.helpersDirectoryName)
        let expectedPlugins = Plugins.test(projectDescriptionHelpers: [.init(name: pluginName, path: expectedHelpersPath, location: .remote)])
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
        let cachedPluginPath = environment.cacheDirectory.appending(components: Constants.pluginsDirectoryName, pluginFingerprint)
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

    private func mockConfig(plugins: [TuistGraph.PluginLocation]) -> TuistGraph.Config {
        Config(
            compatibleXcodeVersions: .all,
            cloud: nil,
            cache: nil,
            plugins: plugins,
            generationOptions: [],
            path: nil
        )
    }
}
