import Foundation
import ProjectDescription
import TSCBasic
import TuistGraph
import TuistSupport

extension TuistGraph.Cache {
    static func from(manifest: ProjectDescription.Cache) -> TuistGraph.Cache {
        TuistGraph.Cache(profiles: manifest.profiles.map(TuistGraph.Cache.Profile.from(manifest:)))
    }
}

extension TuistGraph.Cache.Profile {
    static func from(manifest: ProjectDescription.Cache.Profile) -> TuistGraph.Cache.Profile {
        TuistGraph.Cache.Profile(name: manifest.name, configuration: manifest.configuration)
    }
}
