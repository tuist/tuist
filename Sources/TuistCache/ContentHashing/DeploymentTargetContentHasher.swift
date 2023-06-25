import Foundation
import TuistCore
import TuistGraph

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
        case let .iOS(version, device, supportsMacDesignedForIOS):
            stringToHash = "iOS-\(version)-\(device.rawValue)-\(supportsMacDesignedForIOS)"
        case let .macOS(version):
            stringToHash = "macOS-\(version)"
        case let .watchOS(version):
            stringToHash = "watchOS-\(version)"
        case let .tvOS(version):
            stringToHash = "tvOS-\(version)"
        case let .visionOS(version):
            stringToHash = "visionOS-\(version)"
        }
        return try contentHasher.hash(stringToHash)
    }
}
