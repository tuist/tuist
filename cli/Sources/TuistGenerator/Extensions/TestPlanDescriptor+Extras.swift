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
        guard case let .generated(defaultOptions, options) = testPlan.kind else { return nil }

        let testTargets: [TestPlanDescriptor.TestTarget] = testPlan.testTargets
            .compactMap { testableTarget in
                descriptorTarget(
                    for: testableTarget.target,
                    isEnabled: !testableTarget.isSkipped,
                    parallelization: testableTarget.parallelization,
                    skippedTests: testableTarget.skippedTests,
                    selectedTests: testableTarget.selectedTests,
                    graphTraverser: graphTraverser,
                    generatedProjects: generatedProjects,
                    rootPath: rootPath
                )
            }

        guard !testTargets.isEmpty else { return nil }

        return TestPlanDescriptor(
            path: testPlan.path,
            testTargets: testTargets,
            defaultOptions: descriptorOptions(
                defaultOptions,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            ),
            options: options.mapValues {
                descriptorOptions(
                    $0,
                    graphTraverser: graphTraverser,
                    generatedProjects: generatedProjects,
                    rootPath: rootPath
                )
            }
        )
    }

    private static func descriptorTarget(
        for target: TargetReference,
        isEnabled: Bool = true,
        parallelization: TestableTarget.Parallelization = .none,
        skippedTests: [String] = [],
        selectedTests: [String] = [],
        graphTraverser: GraphTraversing,
        generatedProjects: [AbsolutePath: GeneratedProject],
        rootPath: AbsolutePath
    ) -> TestPlanDescriptor.TestTarget? {
        guard let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name) else {
            return nil
        }
        let projectPath = graphTarget.project.xcodeProjPath
        guard let generatedProject = generatedProjects[projectPath],
              let pbxTarget = generatedProject.targets[graphTarget.target.name]
        else {
            return nil
        }
        let containerRelativePath = projectPath.relative(to: rootPath).pathString
        return TestPlanDescriptor.TestTarget(
            pbxTarget: pbxTarget,
            containerPath: "container:\(containerRelativePath)",
            isEnabled: isEnabled,
            parallelization: parallelization,
            skippedTests: skippedTests,
            selectedTests: selectedTests
        )
    }

    private static func descriptorOptions(
        _ options: TestPlanOptions,
        graphTraverser: GraphTraversing,
        generatedProjects: [AbsolutePath: GeneratedProject],
        rootPath: AbsolutePath
    ) -> TestPlanDescriptor.Options {
        let codeCoverageTargets: [TargetReference]? = if case let .specificTargets(targets) = options.codeCoverage {
            targets
        } else {
            nil
        }
        let resolvedCodeCoverageTargets = codeCoverageTargets?.compactMap { target in
            descriptorTarget(
                for: target,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        }
        let expandVariableFromTarget = options.expandVariableFromTarget.flatMap { target in
            descriptorTarget(
                for: target,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        }
        return TestPlanDescriptor.Options(
            values: options,
            codeCoverageTargets: resolvedCodeCoverageTargets,
            expandVariableFromTarget: expandVariableFromTarget
        )
    }
}
