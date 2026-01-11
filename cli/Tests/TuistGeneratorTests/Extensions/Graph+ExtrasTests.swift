import Foundation
import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph

@testable import TuistGenerator

struct GraphExtrasTests {
    @Test func filter_withSourceTargets_showsDownstreamDependencies() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let coreTarget = Target.test(name: "Core")
        let networkTarget = Target.test(name: "Network", dependencies: [.target(name: "Core")])
        let appTarget = Target.test(name: "App", dependencies: [.target(name: "Network")])

        let project = Project.test(
            path: projectPath,
            targets: [coreTarget, networkTarget, appTarget]
        )

        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .target(name: "Network", path: projectPath),
                ],
                .target(name: "Network", path: projectPath): [
                    .target(name: "Core", path: projectPath),
                ],
                .target(name: "Core", path: projectPath): [],
            ]
        )

        // When
        let result = graph.filter(
            skipTestTargets: false,
            skipExternalDependencies: false,
            platformToFilter: nil,
            targetsToFilter: [],
            sourceTargets: ["App"],
            sinkTargets: [],
            directOnly: false,
            typeFilter: []
        )

        // Then
        let targetNames = Set(result.keys.map(\.target.name))
        #expect(targetNames.contains("App"))
        #expect(targetNames.contains("Network"))
        #expect(targetNames.contains("Core"))
    }

    @Test func filter_withSourceTargetsAndDirectOnly_showsOnlyDirectDependencies() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let coreTarget = Target.test(name: "Core")
        let networkTarget = Target.test(name: "Network", dependencies: [.target(name: "Core")])
        let appTarget = Target.test(name: "App", dependencies: [.target(name: "Network")])

        let project = Project.test(
            path: projectPath,
            targets: [coreTarget, networkTarget, appTarget]
        )

        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .target(name: "Network", path: projectPath),
                ],
                .target(name: "Network", path: projectPath): [
                    .target(name: "Core", path: projectPath),
                ],
                .target(name: "Core", path: projectPath): [],
            ]
        )

        // When
        let result = graph.filter(
            skipTestTargets: false,
            skipExternalDependencies: false,
            platformToFilter: nil,
            targetsToFilter: [],
            sourceTargets: ["App"],
            sinkTargets: [],
            directOnly: true,
            typeFilter: []
        )

        // Then
        let targetNames = Set(result.keys.map(\.target.name))
        #expect(targetNames.contains("App"))
        #expect(targetNames.contains("Network"))
        #expect(!targetNames.contains("Core"))
    }

    @Test func filter_withLabelFilter_filtersToSpecificDependencyTypes() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let frameworkPath = try AbsolutePath(validating: "/Frameworks/External.framework")
        let appTarget = Target.test(name: "App", dependencies: [.target(name: "Core")])
        let coreTarget = Target.test(name: "Core")

        let project = Project.test(
            path: projectPath,
            targets: [appTarget, coreTarget]
        )

        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .target(name: "Core", path: projectPath),
                    .framework(
                        path: frameworkPath,
                        binaryPath: frameworkPath.appending(component: "External"),
                        dsymPath: nil,
                        bcsymbolmapPaths: [],
                        linking: .dynamic,
                        architectures: [.arm64],
                        status: .required
                    ),
                ],
                .target(name: "Core", path: projectPath): [],
            ]
        )

        // When
        let result = graph.filter(
            skipTestTargets: false,
            skipExternalDependencies: false,
            platformToFilter: nil,
            targetsToFilter: [],
            sourceTargets: [],
            sinkTargets: [],
            directOnly: false,
            typeFilter: ["target"]
        )

        // Then
        let appDeps = result.first { $0.key.target.name == "App" }?.value ?? []
        let depLabelNames = appDeps.map(\.labelName)
        #expect(depLabelNames.allSatisfy { $0 == "target" })
    }
}
