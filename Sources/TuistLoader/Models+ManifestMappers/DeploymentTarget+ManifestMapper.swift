import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.DeploymentTarget {
    /// Maps a ProjectDescription.DeploymentTarget instance into a TuistCore.DeploymentTarget instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of deployment target model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.DeploymentTarget) -> TuistCore.DeploymentTarget {
        switch manifest {
        case let .iOS(version, devices):
            return .iOS(version, DeploymentDevice(rawValue: devices.rawValue))
        case let .macOS(version):
            return .macOS(version)
        case let .watchOS(version):
            return .watchOS(version)
        case let .tvOS(version):
            return .tvOS(version)
        }
    }
}
