import Basic
import Foundation
import ProjectDescription
@testable import TuistLoader

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

    public var loadTuistConfigCount: UInt = 0
    public var loadTuistConfigStub: ((AbsolutePath) throws -> ProjectDescription.TuistConfig)?

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

    public func loadTuistConfig(at path: AbsolutePath) throws -> TuistConfig {
        loadTuistConfigCount += 1
        return try loadTuistConfigStub?(path) ?? ProjectDescription.TuistConfig.test()
    }
}
