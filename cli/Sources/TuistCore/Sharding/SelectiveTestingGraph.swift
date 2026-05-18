import Foundation

/// Pre-computed selective testing data persisted during the shard plan phase
/// and restored during the shard execute phase to avoid regenerating
/// the project and rehashing targets.
public struct SelectiveTestingGraph: Codable {
    /// Test target name → hash (incorporates the target and all its transitive dependencies)
    public let testTargetHashes: [String: String]

    /// Names of the test plans (or scheme names, when a scheme has no plans) that
    /// `build-for-testing` was asked to build. Used at `test-without-building` time to
    /// distinguish a fully-pruned plan (skip with success) from a typo'd plan name
    /// (let xcodebuild fail naturally).
    public let attemptedTestPlans: [String]

    public init(
        testTargetHashes: [String: String],
        attemptedTestPlans: [String] = []
    ) {
        self.testTargetHashes = testTargetHashes
        self.attemptedTestPlans = attemptedTestPlans
    }

    public static let fileName = "selective-testing-graph.json"

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        testTargetHashes = try container.decode([String: String].self, forKey: .testTargetHashes)
        attemptedTestPlans =
            try container.decodeIfPresent([String].self, forKey: .attemptedTestPlans) ?? []
    }
}
