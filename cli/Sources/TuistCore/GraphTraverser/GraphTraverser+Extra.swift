import Foundation
import TuistConfig
import XcodeGraph

extension GraphTraversing {
    /// Returns the included based on the parameters.
    public func filterIncludedTargets(
        basedOn targets: some Collection<GraphTarget>,
        testPlan: String?,
        includedTargets: Set<TargetQuery>,
        excludedTargets: Set<TargetQuery>,
        excludingExternalTargets: Bool = false
    ) -> Set<GraphTarget> {
        let allTestPlansTargetNames: Set<String>?
        if includedTargets.isEmpty, let testPlanName = testPlan, let testPlan = self.testPlan(name: testPlanName) {
            allTestPlansTargetNames = Set(testPlan.testTargets.filter { !$0.isSkipped }.map(\.target.name))
        } else {
            allTestPlansTargetNames = nil
        }

        let includedTargetsMatcher = TargetQueryMatcher(includedTargets)
        let excludedTargetsMatcher = TargetQueryMatcher(excludedTargets)

        lazy var allInternalTargets = allInternalTargets().map(\.target.name)
        return Set(
            targets.filter { target in
                if let allTestPlansTargetNames, !allTestPlansTargetNames.contains(target.target.name) {
                    return false
                }
                if !includedTargetsMatcher.isEmpty {
                    return includedTargetsMatcher.matches(
                        targetName: target.target.name,
                        tags: target.target.metadata.tags
                    )
                }
                if excludedTargetsMatcher.matches(targetName: target.target.name, tags: target.target.metadata.tags) {
                    return false
                }
                return excludingExternalTargets ? allInternalTargets.contains(target.target.name) : true
            }
        )
    }
}
