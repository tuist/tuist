import Basic
import Foundation
@testable import TuistLoader

public final class MockManifestFilesLocator: ManifestFilesLocating {
    public var locateStub: [(Manifest, AbsolutePath)]?
    public var locateArgs: [AbsolutePath] = []

    public func locate(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        locateArgs.append(at)
        return locateStub ?? [(.project, at.appending(component: "Project.swift"))]
    }
    
    public func locateAll(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        locateArgs.append(at)
        return locateStub ?? [(.project, at.appending(component: "Project.swift"))]
    }
}
