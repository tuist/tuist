import Foundation
import TuistCore
import TuistGraph

public protocol DeploymentTargetsContentHashing {
    func hash(deploymentTargets: DeploymentTargets) throws -> String
}

/// `DeploymentTargetsContentHasher`
/// is responsible for computing a hash that uniquely identifies a `DeploymentTargets`
public final class DeploymentTargetsContentHasher: DeploymentTargetsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - DeploymentTargetsContentHashing

    public func hash(deploymentTargets: DeploymentTargets) throws -> String {
        let stringToHash: String = deploymentTargets.configuredVersions.map { platform, version in
            "\(platform.caseValue)-\(version)"
        }.joined(separator: ",")

        return try contentHasher.hash(stringToHash)
    }
}
