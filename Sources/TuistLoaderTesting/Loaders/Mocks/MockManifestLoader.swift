import Foundation
import ProjectDescription
import TSCBasic
import TuistSupport
@testable import TuistLoader
@testable import TuistSupportTesting

public final class MockManifestLoader: ManifestLoading {

    public var loadProjectCount: UInt = 0
    public var loadProjectStub: ((AbsolutePath) throws -> ProjectDescription.Project)?

    public var loadWorkspaceCount: UInt = 0
    public var loadWorkspaceStub: ((AbsolutePath) throws -> ProjectDescription.Workspace)?

    public var manifestsAtCount: UInt = 0
    public var manifestsAtStub: ((AbsolutePath) -> Set<Manifest>)?

    public var manifestPathCount: UInt = 0
    public var manifestPathStub: ((AbsolutePath, Manifest) throws -> AbsolutePath)?

    public var loadSetupCount: UInt = 0
    public var loadSetupStub: ((AbsolutePath) throws -> [Upping])?

    public var loadConfigCount: UInt = 0
    public var loadConfigStub: ((AbsolutePath) throws -> ProjectDescription.Config)?

    public var loadTemplateCount: UInt = 0
    public var loadTemplateStub: ((AbsolutePath) throws -> ProjectDescription.Template)?

    public var loadDependenciesCount: UInt = 0
    public var loadDependenciesStub: ((AbsolutePath) throws -> ProjectDescription.Dependencies)?

    public init() {}

    public func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project {
        try loadProjectStub?(path) ?? ProjectDescription.Project.test()
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace {
        try loadWorkspaceStub?(path) ?? ProjectDescription.Workspace.test()
    }

    public func manifests(at path: AbsolutePath) -> Set<Manifest> {
        manifestsAtCount += 1
        return manifestsAtStub?(path) ?? Set()
    }

    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath {
        manifestPathCount += 1
        return try manifestPathStub?(path, manifest) ?? TemporaryDirectory(removeTreeOnDeinit: true).path
    }

    public func loadSetup(at path: AbsolutePath) throws -> [Upping] {
        loadSetupCount += 1
        return try loadSetupStub?(path) ?? []
    }

    public func loadConfig(at path: AbsolutePath) throws -> Config {
        loadConfigCount += 1
        return try loadConfigStub?(path) ?? ProjectDescription.Config.test()
    }

    public func loadTemplate(at path: AbsolutePath) throws -> Template {
        loadTemplateCount += 1
        return try loadTemplateStub?(path) ?? ProjectDescription.Template.test()
    }

    public func loadDependencies(at path: AbsolutePath) throws -> Dependencies {
        loadDependenciesCount += 1
        return try loadDependenciesStub?(path) ?? ProjectDescription.Dependencies.test()
    }
}
