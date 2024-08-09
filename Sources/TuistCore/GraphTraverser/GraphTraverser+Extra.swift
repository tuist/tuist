import Foundation
import XcodeGraph

extension GraphTraversing {
    /// Returns the included based on the parameters.
    public func filterIncludedTargets(
        basedOn targets: some Collection<GraphTarget>,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        excludingExternalTargets: Bool = false
    ) -> Set<GraphTarget> {
        let allTestPlansTargetNames: Set<String>?
        if includedTargets.isEmpty, let testPlanName = testPlan, let testPlan = self.testPlan(name: testPlanName) {
            allTestPlansTargetNames = Set(testPlan.testTargets.filter { !$0.isSkipped }.map(\.target.name))
        } else {
            allTestPlansTargetNames = nil
        }

        lazy var allInternalTargets = allInternalTargets().map(\.target.name)
        return Set(
            targets.filter { target in
                if let allTestPlansTargetNames, !allTestPlansTargetNames.contains(target.target.name) {
                    return false
                }
                if !includedTargets.isEmpty {
                    if target.target.product == .unitTests {
                        let dependencyTargetNames = Set(target.target.dependencies.compactMap { dependency in
                            switch dependency {
                            case let .target(targetName, _), let .project(targetName, _, _):
                                return targetName
                            case .framework, .xcframework, .library, .package, .sdk, .xctest:
                                return nil
                            }
                        })
                        if !dependencyTargetNames.intersection(includedTargets).isEmpty {
                            return true
                        }
                    }
                    return includedTargets.contains(target.target.name)
                }
                if excludedTargets.contains(target.target.name) {
                    return false
                }
                return excludingExternalTargets ? allInternalTargets.contains(target.target.name) : true
            }
        )
    }
}
