import Basic
import Foundation
@testable import TuistKit

final class MockGraphManifestLoader: GraphManifestLoading {
    var loadCount: UInt = 0
    var loadStub: ((Manifest, AbsolutePath) throws -> JSON)?

    var manifestsAtCount: UInt = 0
    var manifestsAtStub: ((AbsolutePath) -> Set<Manifest>)?

    var manifestPathCount: UInt = 0
    var manifestPathStub: ((AbsolutePath, Manifest) throws -> AbsolutePath)?

    var loadSetupCount: UInt = 0
    var loadSetupStub: ((AbsolutePath) throws -> [Upping])?

    func load(_ manifest: Manifest, path: AbsolutePath) throws -> JSON {
        loadCount += 1
        return try loadStub?(manifest, path) ?? JSON([:])
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
