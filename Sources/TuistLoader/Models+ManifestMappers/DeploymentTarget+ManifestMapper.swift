import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.DeploymentTarget {
    static func from(manifest: ProjectDescription.DeploymentTarget) -> TuistCore.DeploymentTarget {
        switch manifest {
        case let .iOS(version, devices):
            return .iOS(version, DeploymentDevice(rawValue: devices.rawValue))
        case let .macOS(version):
            return .macOS(version)
        }
    }
}
