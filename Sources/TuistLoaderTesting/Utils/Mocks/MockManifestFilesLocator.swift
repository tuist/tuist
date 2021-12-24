import Foundation
import TSCBasic
@testable import TuistLoader

public final class MockManifestFilesLocator: ManifestFilesLocating {
    public var locateManifestsArgs: [AbsolutePath] = []
    public var locateManifestsStub: [(Manifest, AbsolutePath)]?
    public var locateProjectManifestsStub: ((AbsolutePath, [String], Bool) -> [ManifestFilesLocator.ProjectManifest])?
    public var locatePluginManifestsStub: [AbsolutePath]?
    public var locatePluginManifestsArgs: [AbsolutePath] = []
    public var locateConfigStub: AbsolutePath?
    public var locateConfigArgs: [AbsolutePath] = []
    public var locateDependenciesStub: AbsolutePath?
    public var locateDependenciesArgs: [AbsolutePath] = []

    public init() {}

    public func locateManifests(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        locateManifestsArgs.append(at)
        return locateManifestsStub ?? [(.project, at.appending(component: "Project.swift"))]
    }

    public func locatePluginManifests(
        at: AbsolutePath,
        excluding _: [String],
        onlyCurrentDirectory _: Bool
    ) -> [AbsolutePath] {
        locatePluginManifestsArgs.append(at)
        return locatePluginManifestsStub ?? [at.appending(component: "Plugin.swift")]
    }

    public func locateProjectManifests(
        at locatingPath: AbsolutePath,
        excluding: [String],
        onlyCurrentDirectory: Bool
    ) -> [ManifestFilesLocator.ProjectManifest] {
        locateProjectManifestsStub?(locatingPath, excluding, onlyCurrentDirectory) ?? [
            ManifestFilesLocator.ProjectManifest(
                manifest: .project,
                path: locatingPath.appending(component: "Project.swift")
            ),
        ]
    }

    public func locateConfig(at: AbsolutePath) -> AbsolutePath? {
        locateConfigArgs.append(at)
        return locateConfigStub ?? at.appending(components: "Tuist", "Config.swift")
    }

    public func locateDependencies(at: AbsolutePath) -> AbsolutePath? {
        locateDependenciesArgs.append(at)
        return locateDependenciesStub ?? at.appending(components: "Tuist", "Dependencies.swift")
    }
}
