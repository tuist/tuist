import Foundation

/// Metadata persisted next to .xctestproducts to describe how selective testing
/// affected test plans during the build-for-testing phase.
public struct SelectiveTestingPlanMetadata: Codable {
    /// Test plans that existed in the original graph but were fully pruned because
    /// all of their targets were already cached as passing.
    public let fullySkippedTestPlans: [String]

    public init(fullySkippedTestPlans: [String] = []) {
        self.fullySkippedTestPlans = fullySkippedTestPlans
    }

    public static let fileName = "selective-testing-plan-metadata.json"

    public func containsFullySkippedTestPlan(named testPlan: String) -> Bool {
        fullySkippedTestPlans.contains(testPlan)
    }
}
