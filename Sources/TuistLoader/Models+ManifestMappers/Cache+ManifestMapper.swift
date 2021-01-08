import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.Cache {
    static func from(manifest: ProjectDescription.Cache) -> TuistCore.Cache {
        TuistCore.Cache(flavors: manifest.flavors.map(TuistCore.Cache.Flavor.from(manifest:)))
    }
}

extension TuistCore.Cache.Flavor {
    static func from(manifest: ProjectDescription.Cache.Flavor) -> TuistCore.Cache.Flavor {
        TuistCore.Cache.Flavor(name: manifest.name, configuration: manifest.configuration)
    }
}
