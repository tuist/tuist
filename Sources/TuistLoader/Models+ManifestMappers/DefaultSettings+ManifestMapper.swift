import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.DefaultSettings {
    static func from(manifest: ProjectDescription.DefaultSettings) -> TuistCore.DefaultSettings {
        switch manifest {
        case .recommended:
            return .recommended
        case .essential:
            return .essential
        case .none:
            return .none
        }
    }
}
