import TuistCore
import TuistGraph

extension GraphTraversing {
    /// Returns the included based on the parameters.
    public func filterIncludedTargets<GraphTargets: Collection>(
        basedOn targets: GraphTargets,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        excludingExternalTargets: Bool = false
    ) -> Set<GraphTarget> where GraphTargets.Element == GraphTarget {
        let allTestPlansTargetNames: Set<String>?
        if includedTargets.isEmpty, let testPlanName = testPlan, let testPlan = self.testPlan(name: testPlanName) {
            allTestPlansTargetNames = Set(testPlan.testTargets.filter(\.isEnabled).map(\.target.name))
        } else {
            allTestPlansTargetNames = nil
        }

        lazy var allInternalTargets = allInternalTargets().map(\.target.name)
        return Set(
            targets.filter { target in
                if !includedTargets.isEmpty {
                    return includedTargets.contains(target.target.name)
                }
                if excludedTargets.contains(target.target.name) {
                    return false
                }
                if let allTestPlansTargetNames = allTestPlansTargetNames {
                    return allTestPlansTargetNames.contains(target.target.name)
                }
                return excludingExternalTargets ? allInternalTargets.contains(target.target.name) : true
            }
        )
    }
}
