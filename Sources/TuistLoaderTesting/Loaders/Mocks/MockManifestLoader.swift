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

    public var loadConfigCount: UInt = 0
    public var loadConfigStub: ((AbsolutePath) throws -> Config)?

    public var loadTemplateCount: UInt = 0
    public var loadTemplateStub: ((AbsolutePath) throws -> Template)?

    public var loadPackageCount: UInt = 0
    public var loadPackageStub: ((AbsolutePath) throws -> PackageInfo)?

    public var loadPackageSettingsCount: UInt = 0
    public var loadPackageSettingsStub: ((AbsolutePath) throws -> PackageSettings)?

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

    public func validateHasRootManifest(at path: AbsolutePath) throws {
        let manifests = manifests(at: path)
        let rootManifests: Set<Manifest> = [.workspace, .project, .package]
        guard !manifests.intersection(rootManifests).isEmpty else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }

    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath {
        manifestPathCount += 1
        return try manifestPathStub?(path, manifest) ?? TemporaryDirectory(removeTreeOnDeinit: true).path
    }

    public func loadConfig(at path: AbsolutePath) throws -> Config {
        loadConfigCount += 1
        return try loadConfigStub?(path) ?? Config.test()
    }

    public func loadTemplate(at path: AbsolutePath) throws -> Template {
        loadTemplateCount += 1
        return try loadTemplateStub?(path) ?? Template.test()
    }

    public func loadPackage(at path: AbsolutePath) throws -> PackageInfo {
        loadPackageCount += 1
        return try loadPackageStub?(path) ?? .test()
    }

    public func loadPackageSettings(at path: AbsolutePath) throws -> PackageSettings {
        loadPackageSettingsCount += 1
        return try loadPackageSettingsStub?(path) ?? .test()
    }

    public func loadPlugin(at path: AbsolutePath) throws -> Plugin {
        loadPluginCount += 1
        return try loadPluginStub?(path) ?? Plugin.test()
    }

    public var taskLoadArgumentsStub: ((AbsolutePath) throws -> [String])?
    public func taskLoadArguments(at path: AbsolutePath) throws -> [String] {
        try taskLoadArgumentsStub?(path) ?? []
    }

    public var registerPluginsCount: UInt = 0
    public var registerPluginsStub: ((Plugins) throws -> Void)?
    public func register(plugins: Plugins) throws {
        registerPluginsCount += 1
        try registerPluginsStub?(plugins)
    }
}
