import Foundation
import ProjectDescription
import TSCBasic
import TuistGraph
import TuistSupport

extension TuistGraph.Cache {
    static func from(manifest: ProjectDescription.Cache) -> TuistGraph.Cache {
        TuistGraph.Cache(flavors: manifest.flavors.map(TuistGraph.Cache.Flavor.from(manifest:)))
    }
}

extension TuistGraph.Cache.Flavor {
    static func from(manifest: ProjectDescription.Cache.Flavor) -> TuistGraph.Cache.Flavor {
        TuistGraph.Cache.Flavor(name: manifest.name, configuration: manifest.configuration)
    }
}
