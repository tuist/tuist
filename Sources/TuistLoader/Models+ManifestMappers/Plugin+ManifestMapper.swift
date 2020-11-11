import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.Plugin {
    static func from(manifest: ProjectDescription.Plugin) throws -> Self {
        switch manifest.pluginType {
        case let .helper(name):
            return .helpers(name: name)
        }
    }
}
