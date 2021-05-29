import Foundation
import ProjectDescription
import TSCBasic
import TuistGraph
import TuistSupport

extension TuistGraph.Cache {
    static func from(manifest: ProjectDescription.Cache,
                     generatorPaths: GeneratorPaths) throws -> TuistGraph.Cache
    {
        let path = try manifest.path.map { try generatorPaths.resolve(path: $0) }
        let profiles = manifest.profiles.map(TuistGraph.Cache.Profile.from(manifest:))
        return TuistGraph.Cache(profiles: profiles, path: path)
    }
}

extension TuistGraph.Cache.Profile {
    static func from(manifest: ProjectDescription.Cache.Profile) -> TuistGraph.Cache.Profile {
        TuistGraph.Cache.Profile(name: manifest.name, configuration: manifest.configuration)
    }
}
