import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.DeploymentTarget: ModelConvertible {
    init(manifest: ProjectDescription.DeploymentTarget, generatorPaths _: GeneratorPaths) throws {
        switch manifest {
        case let .iOS(version, devices):
            self = .iOS(version, DeploymentDevice(rawValue: devices.rawValue))
        case let .macOS(version):
            self = .macOS(version)
        }
    }
}
