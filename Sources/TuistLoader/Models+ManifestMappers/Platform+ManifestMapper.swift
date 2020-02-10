import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Platform {
    static func from(manifest: ProjectDescription.Platform) throws -> TuistCore.Platform {
        switch manifest {
        case .macOS:
            return .macOS
        case .iOS:
            return .iOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        }
    }
}
