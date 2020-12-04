import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.PluginLocation {
    /// Convert from `ProjectDescription.PluginLocation` to `TuistCore.PluginLocation`
    static func from(
        manifest: ProjectDescription.PluginLocation,
        generatorPaths: GeneratorPaths
    ) throws -> TuistCore.PluginLocation {
        switch manifest.type {
        case let .local(path):
            return .local(path: try generatorPaths.resolve(path: path).pathString)
        case let .gitWithBranch(url, branch):
            return .gitWithBranch(url: url, branch: branch)
        case let .gitWithTag(url, tag):
            return .gitWithTag(url: url, tag: tag)
        case let .gitWithSha(url, sha):
            return .gitWithSha(url: url, sha: sha)
        }
    }
}
