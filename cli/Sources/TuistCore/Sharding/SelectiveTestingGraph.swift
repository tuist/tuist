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

    /// The test identifiers the build was restricted to, as `Target[/Suite[/Test]]`. xcodebuild
    /// records a test plan's selection in the `.xctestrun` but never a command-line `-only-testing`,
    /// so a later `test-without-building` has no other way to know what the build was asked for.
    public let requestedTestIdentifiers: [String]

    /// Test target name → metadata tags, for resolving tag queries without regenerating the project.
    /// Nil for bundles produced before target tags were persisted.
    public let testTargetTags: [String: Set<String>]?

    /// The test targets the products hold once selective testing dropped the ones it skipped. Nil for
    /// bundles produced before these were persisted.
    public let builtTestTargetNames: [String]?

    /// The test targets the shard plan split across more than one shard, with the shards holding part of
    /// each. A shard passing its part of one of these does not show the target passed, so its hash is
    /// stored only once every one of those shards passed its part. Set once the plan is created; nil for
    /// unsharded products and for bundles produced before split targets were persisted.
    public var splitTestTargets: SplitTestTargets?

    public struct SplitTestTargets: Codable, Equatable {
        public let shardPlanId: String
        /// Test target name → indices of the shards holding part of it.
        public let shardIndices: [String: [Int]]

        public init(shardPlanId: String, shardIndices: [String: [Int]]) {
            self.shardPlanId = shardPlanId
            self.shardIndices = shardIndices
        }
    }

    public init(
        testTargetHashes: [String: String],
        attemptedTestPlans: [String] = [],
        requestedTestIdentifiers: [String] = [],
        testTargetTags: [String: Set<String>]? = nil,
        builtTestTargetNames: [String]? = nil
    ) {
        self.testTargetHashes = testTargetHashes
        self.attemptedTestPlans = attemptedTestPlans
        self.requestedTestIdentifiers = requestedTestIdentifiers
        self.testTargetTags = testTargetTags
        self.builtTestTargetNames = builtTestTargetNames
    }

    public static let fileName = "selective-testing-graph.json"

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        testTargetHashes = try container.decode([String: String].self, forKey: .testTargetHashes)
        attemptedTestPlans =
            try container.decodeIfPresent([String].self, forKey: .attemptedTestPlans) ?? []
        requestedTestIdentifiers =
            try container.decodeIfPresent([String].self, forKey: .requestedTestIdentifiers) ?? []
        testTargetTags = try container.decodeIfPresent([String: Set<String>].self, forKey: .testTargetTags)
        builtTestTargetNames = try container.decodeIfPresent([String].self, forKey: .builtTestTargetNames)
        splitTestTargets = try container.decodeIfPresent(SplitTestTargets.self, forKey: .splitTestTargets)
    }
}
