import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.SDKStatus {
    static func from(manifest: ProjectDescription.SDKStatus) -> TuistCore.SDKStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        }
    }
}
