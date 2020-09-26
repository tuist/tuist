import Foundation
import TSCBasic
@testable import TuistLoader

public final class MockManifestFilesLocator: ManifestFilesLocating {
    public var locateProjectManifestsStub: [(Manifest, AbsolutePath)]?
    public var locateProjectManifestsArgs: [AbsolutePath] = []
    public var locateAllProjectManifestsStubs: [(Manifest, AbsolutePath)]?
    public var locateAllProjectManifestsArgs: [AbsolutePath] = []
    public var locateConfigStub: AbsolutePath?
    public var locateConfigArgs: [AbsolutePath] = []
    public var locateSetupStub: AbsolutePath?
    public var locateSetupArgs: [AbsolutePath] = []

    public func locateProjectManifests(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        locateProjectManifestsArgs.append(at)
        return locateProjectManifestsStub ?? [(.project, at.appending(component: "Project.swift"))]
    }

    public func locateAllProjectManifests(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        locateAllProjectManifestsArgs.append(at)
        return locateAllProjectManifestsStubs ?? [(.project, at.appending(component: "Project.swift"))]
    }

    public func locateConfig(at: AbsolutePath) -> AbsolutePath? {
        locateConfigArgs.append(at)
        return locateConfigStub ?? at.appending(components: "Tuist", "Config.swift")
    }

    public func locateSetup(at: AbsolutePath) -> AbsolutePath? {
        locateSetupArgs.append(at)
        return locateSetupStub ?? at.appending(component: "Setup.swift")
    }
}
