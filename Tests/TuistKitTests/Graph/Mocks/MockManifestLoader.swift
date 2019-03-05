import Basic
import Foundation
import ProjectDescription
@testable import TuistKit

final class MockGraphManifestLoader: GraphManifestLoading {
    var loadProjectCount: UInt = 0
    var loadProjectStub: ((AbsolutePath) throws -> ProjectDescription.Project)?

    var loadWorkspaceCount: UInt = 0
    var loadWorkspaceStub: ((AbsolutePath) throws -> ProjectDescription.Workspace)?

    var manifestsAtCount: UInt = 0
    var manifestsAtStub: ((AbsolutePath) -> Set<Manifest>)?

    var manifestPathCount: UInt = 0
    var manifestPathStub: ((AbsolutePath, Manifest) throws -> AbsolutePath)?

    var loadSetupCount: UInt = 0
    var loadSetupStub: ((AbsolutePath) throws -> [Upping])?

    func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project {
        return try loadProjectStub?(path) ?? ProjectDescription.Project.test()
    }

    func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace {
        return try loadWorkspaceStub?(path) ?? ProjectDescription.Workspace.test()
    }

    func manifests(at path: AbsolutePath) -> Set<Manifest> {
        manifestsAtCount += 1
        return manifestsAtStub?(path) ?? Set()
    }

    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath {
        manifestPathCount += 1
        return try manifestPathStub?(path, manifest) ?? TemporaryDirectory(removeTreeOnDeinit: true).path
    }

    func loadSetup(at path: AbsolutePath) throws -> [Upping] {
        loadSetupCount += 1
        return try loadSetupStub?(path) ?? []
    }
}
