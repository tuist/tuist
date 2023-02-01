import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.PluginLocation {
    /// Convert from `ProjectDescription.PluginLocation` to `TuistGraph.PluginLocation`
    static func from(
        manifest: ProjectDescription.PluginLocation,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.PluginLocation {
        switch manifest.type {
        case let .local(path):
            return .local(path: try generatorPaths.resolve(path: path).pathString)
        case let .gitWithTag(url, tag, directory, releaseUrl):
            return .git(url: url, gitReference: .tag(tag), directory: directory, releaseUrl: releaseUrl)
        case let .gitWithSha(url, sha, directory):
            return .git(url: url, gitReference: .sha(sha), directory: directory, releaseUrl: nil)
        }
    }
}
