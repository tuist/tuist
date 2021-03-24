import Foundation
import ProjectDescription
import TSCBasic
import struct TuistGraph.Plugins
import TuistSupport
@testable import TuistLoader
@testable import TuistSupportTesting

public final class MockManifestLoader: ManifestLoading {
    public var loadProjectCount: UInt = 0
    public var loadProjectStub: ((AbsolutePath) throws -> Project)?

    public var loadWorkspaceCount: UInt = 0
    public var loadWorkspaceStub: ((AbsolutePath) throws -> Workspace)?

    public var manifestsAtCount: UInt = 0
    public var manifestsAtStub: ((AbsolutePath) -> Set<Manifest>)?

    public var manifestPathCount: UInt = 0
    public var manifestPathStub: ((AbsolutePath, Manifest) throws -> AbsolutePath)?

    public var loadSetupCount: UInt = 0
    public var loadSetupStub: ((AbsolutePath) throws -> SetupActions)?

    public var loadConfigCount: UInt = 0
    public var loadConfigStub: ((AbsolutePath) throws -> Config)?

    public var loadTemplateCount: UInt = 0
    public var loadTemplateStub: ((AbsolutePath) throws -> Template)?

    public var loadDependenciesCount: UInt = 0
    public var loadDependenciesStub: ((AbsolutePath) throws -> Dependencies)?

    public var loadPluginCount: UInt = 0
    public var loadPluginStub: ((AbsolutePath) throws -> Plugin)?

    public init() {}

    public func loadProject(at path: AbsolutePath) throws -> Project {
        try loadProjectStub?(path) ?? Project.test()
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> Workspace {
        try loadWorkspaceStub?(path) ?? Workspace.test()
    }

    public func manifests(at path: AbsolutePath) -> Set<Manifest> {
        manifestsAtCount += 1
        return manifestsAtStub?(path) ?? Set()
    }

    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath {
        manifestPathCount += 1
        return try manifestPathStub?(path, manifest) ?? TemporaryDirectory(removeTreeOnDeinit: true).path
    }

    public func loadSetup(at path: AbsolutePath) throws -> SetupActions {
        loadSetupCount += 1
        return try loadSetupStub?(path) ?? SetupActions(actions: [], requires: [])
    }

    public func loadConfig(at path: AbsolutePath) throws -> Config {
        loadConfigCount += 1
        return try loadConfigStub?(path) ?? Config.test()
    }

    public func loadTemplate(at path: AbsolutePath) throws -> Template {
        loadTemplateCount += 1
        return try loadTemplateStub?(path) ?? Template.test()
    }

    public func loadDependencies(at path: AbsolutePath) throws -> Dependencies {
        loadDependenciesCount += 1
        return try loadDependenciesStub?(path) ?? Dependencies.test()
    }

    public func loadPlugin(at path: AbsolutePath) throws -> Plugin {
        loadPluginCount += 1
        return try loadPluginStub?(path) ?? Plugin.test()
    }

    public func register(plugins _: Plugins) {}
}
