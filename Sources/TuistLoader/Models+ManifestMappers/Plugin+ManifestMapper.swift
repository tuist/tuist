import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.Plugin {
    static func from(manifest: ProjectDescription.Plugin) throws -> Self {
        TuistCore.Plugin(name: manifest.name)
    }
}
