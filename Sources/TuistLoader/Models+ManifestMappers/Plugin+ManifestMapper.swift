import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import TuistGraph

extension TuistGraph.Plugin {
    static func from(manifest: ProjectDescription.Plugin) throws -> Self {
        TuistGraph.Plugin(name: manifest.name)
    }
}
