import Foundation
import Path
import TuistCore
import XcodeGraph

extension TestPlanDescriptor {
    /// Builds a descriptor for a generated test plan from the graph and the generated projects
    /// that own its targets. Returns `nil` when the plan isn't Tuist-generated or when none of
    /// its test targets can be resolved.
    static func from(
        testPlan: TestPlan,
        graphTraverser: GraphTraversing,
        generatedProjects: [AbsolutePath: GeneratedProject],
        rootPath: AbsolutePath
    ) -> TestPlanDescriptor? {
        guard testPlan.kind == .generated else { return nil }

        var testTargets: [TestPlanDescriptor.TestTarget] = []
        for testableTarget in testPlan.testTargets {
            guard let graphTarget = graphTraverser.target(
                path: testableTarget.target.projectPath,
                name: testableTarget.target.name
            ) else {
                continue
            }
            let projectPath = graphTarget.project.xcodeProjPath
            guard let generatedProject = generatedProjects[projectPath],
                  let pbxTarget = generatedProject.targets[graphTarget.target.name]
            else {
                continue
            }
            let containerRelativePath = projectPath.relative(to: rootPath).pathString
            testTargets.append(
                TestPlanDescriptor.TestTarget(
                    pbxTarget: pbxTarget,
                    containerPath: "container:\(containerRelativePath)",
                    isEnabled: !testableTarget.isSkipped,
                    parallelization: testableTarget.parallelization
                )
            )
        }

        guard !testTargets.isEmpty else { return nil }

        return TestPlanDescriptor(path: testPlan.path, testTargets: testTargets)
    }
}
