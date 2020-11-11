import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
@testable import TuistLoader
@testable import TuistSupportTesting

public final class MockManifestLoader: ManifestLoading {
    public var loadProjectCount: UInt = 0
    public var loadProjectStub: ((AbsolutePath, Plugins) throws -> ProjectDescription.Project)?

    public var loadWorkspaceCount: UInt = 0
    public var loadWorkspaceStub: ((AbsolutePath, Plugins) throws -> ProjectDescription.Workspace)?

    public var manifestsAtCount: UInt = 0
    public var manifestsAtStub: ((AbsolutePath) -> Set<Manifest>)?

    public var manifestPathCount: UInt = 0
    public var manifestPathStub: ((AbsolutePath, Manifest) throws -> AbsolutePath)?

    public var loadSetupCount: UInt = 0
    public var loadSetupStub: ((AbsolutePath, Plugins) throws -> [Upping])?

    public var loadConfigCount: UInt = 0
    public var loadConfigStub: ((AbsolutePath) throws -> ProjectDescription.Config)?

    public var loadTemplateCount: UInt = 0
    public var loadTemplateStub: ((AbsolutePath, Plugins) throws -> ProjectDescription.Template)?

    public var loadDependenciesCount: UInt = 0
    public var loadDependenciesStub: ((AbsolutePath, Plugins) throws -> ProjectDescription.Dependencies)?

    public var loadPluginCount: UInt = 0
    public var loadPluginStub: ((AbsolutePath) throws -> ProjectDescription.Plugin)?

    public init() {}

    public func loadProject(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Project {
        try loadProjectStub?(path, plugins) ?? ProjectDescription.Project.test()
    }

    public func loadWorkspace(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Workspace {
        try loadWorkspaceStub?(path, plugins) ?? ProjectDescription.Workspace.test()
    }

    public func manifests(at path: AbsolutePath) -> Set<Manifest> {
        manifestsAtCount += 1
        return manifestsAtStub?(path) ?? Set()
    }

    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath {
        manifestPathCount += 1
        return try manifestPathStub?(path, manifest) ?? TemporaryDirectory(removeTreeOnDeinit: true).path
    }

    public func loadSetup(at path: AbsolutePath, plugins: Plugins) throws -> [Upping] {
        loadSetupCount += 1
        return try loadSetupStub?(path, plugins) ?? []
    }

    public func loadConfig(at path: AbsolutePath) throws -> ProjectDescription.Config {
        loadConfigCount += 1
        return try loadConfigStub?(path) ?? ProjectDescription.Config.test()
    }

    public func loadTemplate(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Template {
        loadTemplateCount += 1
        return try loadTemplateStub?(path, plugins) ?? ProjectDescription.Template.test()
    }

    public func loadDependencies(at path: AbsolutePath, plugins: Plugins) throws -> Dependencies {
        loadDependenciesCount += 1
        return try loadDependenciesStub?(path, plugins) ?? ProjectDescription.Dependencies.test()
    }

    public func loadPlugin(at path: AbsolutePath) throws -> ProjectDescription.Plugin {
        loadPluginCount += 1
        return try loadPluginStub?(path) ?? ProjectDescription.Plugin.test()
    }
}
