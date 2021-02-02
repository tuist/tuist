import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistLoader
import TuistLoaderTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistPlugin

final class PluginServiceTests: TuistTestCase {
    private var mockModelLoader: MockGeneratorModelLoader!
    private var mockGitHandler: MockGitHandler!
    private var mockManifestFilesLocator: MockManifestFilesLocator!
    private var subject: PluginService!

    override func setUp() {
        super.setUp()
        do {
            let tuistPath = try temporaryPath().appending(RelativePath("Tuist"))
            mockModelLoader = MockGeneratorModelLoader(basePath: tuistPath)
            mockGitHandler = MockGitHandler()
            mockManifestFilesLocator = MockManifestFilesLocator()
            subject = PluginService(
                modelLoader: mockModelLoader,
                fileHandler: fileHandler,
                gitHandler: mockGitHandler,
                manifestFilesLocator: mockManifestFilesLocator
            )
        } catch {
            XCTFail("Failed initializing PluginServiceTests")
        }
    }

    override func tearDown() {
        super.tearDown()
    }

    func test_loadPlugins_atPath_WHEN_localHelpers() throws {
        let pluginPath = "/path/to/plugin"

        mockModelLoader.mockConfig("Config.swift") { _ in
            self.mockConfig(plugins: [.local(path: pluginPath)])
        }
        mockModelLoader.mockPlugin(pluginPath) { _ in
            Plugin(name: "MockPlugin")
        }
        fileHandler.stubExists = { _ in
            true
        }

        let plugins = try subject.loadPlugins(at: try temporaryPath())
        let expectedPlugins = Plugins(projectDescriptionHelpers: [
            .init(name: "MockPlugin", path: AbsolutePath(pluginPath).appending(component: Constants.helpersDirectoryName)),
        ])

        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_usingConfig_WHEN_localHelpers() throws {
        let pluginPath = "/path/to/plugin"
        let config = mockConfig(plugins: [.local(path: pluginPath)])

        mockModelLoader.mockPlugin(pluginPath) { _ in
            Plugin(name: "MockPlugin")
        }
        fileHandler.stubExists = { _ in
            true
        }

        let plugins = try subject.loadPlugins(using: config)
        let expectedPlugins = Plugins(projectDescriptionHelpers: [
            .init(name: "MockPlugin", path: AbsolutePath(pluginPath).appending(component: Constants.helpersDirectoryName)),
        ])

        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugin_atPath_WHEN_gitHelpers() throws {
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitId = "main"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitId)".md5
        let cachedPluginPath = environment.cacheDirectory.appending(components: Constants.PluginDirectory.name, pluginFingerprint)

        mockModelLoader.mockConfig("Config.swift") { _ in
            self.mockConfig(plugins: [.gitWithBranch(url: pluginGitUrl, branch: pluginGitId)])
        }
        mockModelLoader.mockPlugin(cachedPluginPath.pathString) { _ in
            Plugin(name: "MockPlugin")
        }
        fileHandler.stubExists = { _ in
            true
        }

        let plugins = try subject.loadPlugins(at: try temporaryPath())
        let expectedPlugins = Plugins(projectDescriptionHelpers: [
            .init(name: "MockPlugin", path: cachedPluginPath.appending(component: Constants.helpersDirectoryName)),
        ])

        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugin_usingConfig_WHEN_gitHelpers() throws {
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitId = "main"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitId)".md5
        let cachedPluginPath = environment.cacheDirectory.appending(components: Constants.PluginDirectory.name, pluginFingerprint)
        let config = mockConfig(plugins: [.gitWithBranch(url: pluginGitUrl, branch: pluginGitId)])

        mockModelLoader.mockPlugin(cachedPluginPath.pathString) { _ in
            Plugin(name: "MockPlugin")
        }
        fileHandler.stubExists = { _ in
            true
        }

        let plugins = try subject.loadPlugins(using: config)
        let expectedPlugins = Plugins(projectDescriptionHelpers: [
            .init(name: "MockPlugin", path: cachedPluginPath.appending(component: Constants.helpersDirectoryName)),
        ])

        XCTAssertEqual(plugins, expectedPlugins)
    }

    private func mockConfig(plugins: [PluginLocation]) -> Config {
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
