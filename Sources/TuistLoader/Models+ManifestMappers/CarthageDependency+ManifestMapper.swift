import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.CarthageDependency {
    /// Maps a ProjectDescription.Dependency instance into a TuistCore.CarthageDependency model.
    /// - Parameter manifest: Manifest representation of dependency.
    static func from(manifest: ProjectDescription.Dependency) -> Self {
        switch manifest.requirement {
        case .exact(let version):
            return Self(name: manifest.name, requirement: .exact(version.description))
        }
    }
}
