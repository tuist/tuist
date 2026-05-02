import Foundation

/// Pre-computed selective testing data persisted during the shard plan phase
/// and restored during the shard execute phase to avoid regenerating
/// the project and rehashing targets.
public struct SelectiveTestingGraph: Codable {
    /// Test target name → hash (incorporates the target and all its transitive dependencies)
    public let testTargetHashes: [String: String]
    /// Test plan name → original test target names before selective testing pruned cached targets.
    public let testPlanTargetNames: [String: [String]]

    public init(
        testTargetHashes: [String: String],
        testPlanTargetNames: [String: [String]] = [:]
    ) {
        self.testTargetHashes = testTargetHashes
        self.testPlanTargetNames = testPlanTargetNames
    }

    public static let fileName = "selective-testing-graph.json"

    enum CodingKeys: String, CodingKey {
        case testTargetHashes
        case testPlanTargetNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        testTargetHashes = try container.decode([String: String].self, forKey: .testTargetHashes)
        testPlanTargetNames =
            try container.decodeIfPresent([String: [String]].self, forKey: .testPlanTargetNames) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(testTargetHashes, forKey: .testTargetHashes)
        try container.encode(testPlanTargetNames, forKey: .testPlanTargetNames)
    }
}
