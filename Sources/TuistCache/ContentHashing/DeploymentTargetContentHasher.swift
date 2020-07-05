import Foundation
import TuistCore

public protocol DeploymentTargetContentHashing {
    func hash(deploymentTarget: DeploymentTarget) throws -> String
}

/// `DeploymentTargetContentHasher`
/// is responsible for computing a hash that uniquely identifies a `DeploymentTarget`
public final class DeploymentTargetContentHasher: DeploymentTargetContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - DeploymentTargetContentHashing

    public func hash(deploymentTarget: DeploymentTarget) throws -> String {
        let stringToHash: String
        switch deploymentTarget {
        case let .iOS(version, device):
            stringToHash = "iOS-\(version)-\(device.rawValue)"
        case let .macOS(version):
            stringToHash = "macOS-\(version)"
        }
        return try contentHasher.hash(stringToHash)
    }
}
