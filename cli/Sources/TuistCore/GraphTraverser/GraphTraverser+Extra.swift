import Foundation
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

        var includedTargetNames = Set<String>()
        var includedTargetTags = Set<String>()
        var includedTargetProducts = Set<Product>()
        for includedTarget in includedTargets {
            switch includedTarget {
            case let .named(name):
                includedTargetNames.insert(name)
            case let .tagged(tag):
                includedTargetTags.insert(tag)
            case let .product(product):
                includedTargetProducts.insert(product)
            }
        }

        var excludedTargetNames = Set<String>()
        var excludedTargetTags = Set<String>()
        var excludedTargetProducts = Set<Product>()
        for excludedTarget in excludedTargets {
            switch excludedTarget {
            case let .named(name):
                excludedTargetNames.insert(name)
            case let .tagged(tag):
                excludedTargetTags.insert(tag)
            case let .product(product):
                excludedTargetProducts.insert(product)
            }
        }

        lazy var allInternalTargets = allInternalTargets().map(\.target.name)
        return Set(
            targets.filter { target in
                if let allTestPlansTargetNames, !allTestPlansTargetNames.contains(target.target.name) {
                    return false
                }
                if !includedTargets.isEmpty {
                    return
                        includedTargetNames.contains(target.target.name) ||
                        !includedTargetTags.isDisjoint(with: target.target.metadata.tags) ||
                        includedTargetProducts.contains(target.target.product)
                }
                if excludedTargetNames.contains(target.target.name) {
                    return false
                }
                if !excludedTargetTags.isDisjoint(with: target.target.metadata.tags) {
                    return false
                }
                if excludedTargetProducts.contains(target.target.product) {
                    return false
                }
                return excludingExternalTargets ? allInternalTargets.contains(target.target.name) : true
            }
        )
    }
}
