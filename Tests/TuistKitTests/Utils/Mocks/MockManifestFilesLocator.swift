import Basic
import Foundation
@testable import TuistKit

final class MockManifestFilesLocator: ManifestFilesLocating {
    var locateStub: [(Manifest, AbsolutePath)]?
    var locateArgs: [AbsolutePath] = []

    func locate(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        locateArgs.append(at)
        if let locateStub = locateStub { return locateStub }
        return [(.project, at.appending(component: "Project.swift"))]
    }
}
