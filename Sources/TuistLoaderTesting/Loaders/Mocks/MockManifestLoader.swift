import Basic
import Foundation
import ProjectDescription
import TuistSupport
@testable import TuistLoader

public final class MockManifestLoader: ManifestLoading {
    public var loadProjectCount: UInt = 0
    public var loadProjectStub: ((AbsolutePath, Versions) throws -> ProjectDescription.Project)?

    public var loadWorkspaceCount: UInt = 0
    public var loadWorkspaceStub: ((AbsolutePath, Versions) throws -> ProjectDescription.Workspace)?

    public var manifestsAtCount: UInt = 0
    public var manifestsAtStub: ((AbsolutePath) -> Set<Manifest>)?

    public var manifestPathCount: UInt = 0
    public var manifestPathStub: ((AbsolutePath, Manifest) throws -> AbsolutePath)?

    public var loadSetupCount: UInt = 0
    public var loadSetupStub: ((AbsolutePath, Versions) throws -> [Upping])?

    public var loadConfigCount: UInt = 0
    public var loadConfigStub: ((AbsolutePath, Versions) throws -> ProjectDescription.Config)?

    public var loadTemplateCount: UInt = 0
    public var loadTemplateStub: ((AbsolutePath, Versions) throws -> ProjectDescription.Template)?

    public init() {}

    public func loadProject(at path: AbsolutePath, versions: Versions) throws -> ProjectDescription.Project {
        try loadProjectStub?(path, versions) ?? ProjectDescription.Project.test()
    }

    public func loadWorkspace(at path: AbsolutePath, versions: Versions) throws -> ProjectDescription.Workspace {
        try loadWorkspaceStub?(path, versions) ?? ProjectDescription.Workspace.test()
    }

    public func manifests(at path: AbsolutePath) -> Set<Manifest> {
        manifestsAtCount += 1
        return manifestsAtStub?(path) ?? Set()
    }

    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath {
        manifestPathCount += 1
        return try manifestPathStub?(path, manifest) ?? TemporaryDirectory(removeTreeOnDeinit: true).path
    }

    public func loadSetup(at path: AbsolutePath, versions: Versions) throws -> [Upping] {
        loadSetupCount += 1
        return try loadSetupStub?(path, versions) ?? []
    }

    public func loadConfig(at path: AbsolutePath, versions: Versions) throws -> Config {
        loadConfigCount += 1
        return try loadConfigStub?(path, versions) ?? ProjectDescription.Config.test()
    }

    public func loadTemplate(at path: AbsolutePath, versions: Versions) throws -> Template {
        loadTemplateCount += 1
        return try loadTemplateStub?(path, versions) ?? ProjectDescription.Template.test()
    }
}
